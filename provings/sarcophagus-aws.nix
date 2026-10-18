# Proving: sarcophagus-aws cogitator
#
# Builds the raw disk image the profile exists to produce, boots it on a disk
# *larger than the image*, and asserts the one claim nothing else in this suite
# can reach: the ZFS pool grows to fill the volume underneath it.
#
# That is the situation of every EC2 instance launched from this AMI on an EBS
# volume bigger than the image, and `stc-grow-pool` in relics/nixos/aws.nix is
# the code that handles it. Until this proving, that code had no coverage at all:
# provings/dreadnought.nix only reads the *string* of its script, and
# provings/sarcophagus-kvm.nix boots a disk exactly the size of its image, so
# there is nothing there to grow.
#
# ---------------------------------------------------------------------------
# The bench: the external-image pattern, reused
#
# This follows provings/sarcophagus-kvm.nix, which follows nixpkgs' own
# nixos/tests/qemu-vm-external-disk-image.nix: the node declares the image, and
# the driver boots *that image* instead of synthesising a root. The five node
# options below are concessions to the bench, not product fixes — upstream
# exposes every one of them for exactly this purpose, and the KVM proving's
# header documents what each one measured.
#
# Exactly two things differ from the KVM proving:
#
#   1. The image is raw, not qcow2. Measured in make-single-disk-zfs-image.nix
#      (lines 82-91): `format = "raw"` maps to the suffix ".img", so the file is
#      $out/nixos.root.img and qemu-img needs `-F raw`.
#   2. The overlay is given a size — 8 GiB over a 5 GiB image. That is the whole
#      point; see the pool-growth subtest.
#
# The five concession lines and the qemu-img block are *copied*, not factored
# out into something shared. Two occurrences do not make an abstraction, and a
# helper would hide precisely the lines a reader needs in front of them to trust
# the bench. If a third sarcophagus ever arrives, factor it then, with three
# cases in view.
#
# ---------------------------------------------------------------------------
# One boot, and what is deliberately not re-asserted
#
# The KVM proving boots twice to prove the @blank rollback. This one boots once.
#
# Impermanence, the rollback, the creation of @blank and the survival of the SSH
# host keys all come from relics/nixos/impermanence.nix — the *same* relic,
# already proven by sarcophagus-kvm on a real pool, in both directions, with the
# mechanism explained. Repeating it here would add a second image build and a
# second boot to the heaviest line of `just test` in order to measure the same
# code twice. A gate too heavy to run stops being a gate.
#
# So this proving asserts what is specific to AWS. Each candidate assertion was
# measured on a bare nixosTest node and on a node carrying only
# `boot.supportedFilesystems = ["zfs"]`, before being written. What that
# measurement disqualified, and why:
#
#   - boot.zfs.devNodes ("/dev", against the default "/dev/disk/by-id"). It
#     discriminates in evaluation and *cannot* be observed here: the only runtime
#     reading would be the store path of a unit script interpolated from the same
#     evaluation, which is a tautology — and a virtio disk does have by-id
#     entries, so the default would import the pool just as well. The bench
#     cannot tell the relic from the default.
#   - networking.timeServers (the AWS-internal 169.254.169.123). Measured:
#     services.timesyncd.enable is false on all three nodes, so no
#     /etc/systemd/timesyncd.conf is rendered at all. It is qemu-vm.nix:1489
#     that turns it off — a bare `false` at normal priority, commented "Don't
#     run ntpd in the guest" — and not nixos-test-base.nix, which never mentions
#     timesyncd. The AWS NTP endpoint stays uncovered, as for dreadnought.
#   - the serial console. The getty loses an ordinary priority contest to the
#     test instrumentation (it has been lib.mkDefault since #45, which is what
#     made any proving of this profile possible). As for the
#     `console=ttyS0,115200n8` string: v0.14.0 measured it non-discriminating
#     because the test base sets virtualisation.qemu.consoles, which arrives
#     through qemu's -append. Under this pattern directBoot is off and the kernel
#     command line comes from the image's own GRUB, so the string *might*
#     discriminate here — but establishing that would mean building a second
#     image without the relic, which this proving does not pay for. So it is not
#     asserted, rather than asserted on an unverified premise.
#   - services.udisks2.enable = false. Measured false on a bare node too.
#   - the partition layout (bios_grub + ESP + ZFS): produced by
#     make-single-disk-zfs-image.nix, so asserting it would measure nixpkgs.
#   - the disko.devices block of the cogitator, which is descriptive and whose
#     own comment says it does not partition the image.
# ---------------------------------------------------------------------------
{self}: {
  name = "sarcophagus-aws";

  nodes.machine = {lib, ...}: {
    imports = [self.nixosModules.cogitator-sarcophagus-aws];

    stc.cogitator.sarcophagus-aws = {
      enable = true;

      # The bench's disk is virtio, and this is the heart of the proving.
      #
      # With the default "nvme0n1" there is no such device here. Measured, on a
      # device that is genuinely absent: `growpart` exits **2**, and the relic
      # tolerates only 1 (a no-op growth), so stc-grow-pool fails. The only
      # thing left to assert would then be that a unit failed — which measures
      # the bench, not STC. Moving the option
      # does three things at once: the growth path actually runs against a real
      # partition table, the cogitator → relic threading of the option is proven
      # rather than assumed, and "vda" does not end in a digit so it exercises
      # the partSep = "" branch of the relic's device-naming rule (the xvd*/sd*
      # case, i.e. Xen instances). Measured: the rendered script is
      # `growpart /dev/vda 3` then `zpool online -e vmpool /dev/vda3`.
      ebsDisk = "vda";
    };

    # Required by the ZFS relic's upstream assertion, exactly as the three
    # schematics set it. This node imports a real pool, so it is load-bearing.
    networking.hostId = "deadbeef";

    # The five bench concessions — see provings/sarcophagus-kvm.nix for what
    # each one measured. They are identical here.
    virtualisation.directBoot.enable = false;
    virtualisation.mountHostNixStore = false;
    virtualisation.fileSystems = lib.mkForce {};
    virtualisation.bootLoaderDevice = "/dev/vda";
    system.switch.enable = true;
  };

  testScript = {nodes, ...}: ''
    import os
    import subprocess
    import tempfile

    # A copy-on-write overlay over the image in the store, which is read-only.
    #
    # The trailing size is what distinguishes this proving from the KVM one.
    # Three sizes are in play here and collapsing any two of them gets the
    # arithmetic wrong, so all three are named — measured on the built artefact:
    #
    #   - the ZFS partition (p3) is 4096 MiB, which is `rootSize`;
    #   - the image *file* is 5120 MiB, because upstream creates it at
    #     `bootSize + rootSize` and `bootSize` defaults to 1024, which the
    #     cogitator does not pass — the `qemu-img create` line of that file
    #     sizes the file as the sum of the two;
    #   - the virtual disk this overlay exposes is 8 GiB.
    #
    # So p3 ends ~4 GiB into an 8 GiB device, and there is something for growpart
    # to grow. That is an EC2 instance on an EBS volume larger than its AMI,
    # which is the case stc-grow-pool exists for.
    #
    # -F raw, not qcow2: make-single-disk-zfs-image.nix maps format = "raw" to
    # the ".img" suffix.
    overlay = tempfile.NamedTemporaryFile(suffix=".qcow2", delete=False)
    subprocess.run(
        [
            "${nodes.machine.virtualisation.qemu.package}/bin/qemu-img",
            "create", "-f", "qcow2",
            "-b", "${nodes.machine.system.build.awsImage}/nixos.root.img",
            "-F", "raw",
            overlay.name,
            "8G",
        ],
        check=True,
    )
    os.environ["NIX_DISK_IMAGE"] = overlay.name

    machine.start()
    machine.wait_for_unit("multi-user.target")

    with subtest("the AWS image comes up with nothing failing"):
        # `running`, not `degraded`. On this profile that single line catches any
        # regression that leaves a unit failing at boot — and it is only
        # reachable because ebsDisk matches the bench's disk, so stc-grow-pool
        # succeeds instead of failing on a missing device.
        state = machine.succeed("systemctl is-system-running --wait || true").strip()
        assert state == "running", f"unexpected system state: {state}"

    with subtest("the profile's own ZFS datasets are what is mounted"):
        # SOURCE and FSTYPE, not merely "/ is mounted": with the qemu-vm
        # fileSystems override back in place this would be the driver's own disk
        # and a bare mount check would still pass.
        for path, source in [
            ("/", "vmpool/root"),
            ("/nix", "vmpool/nix"),
            ("/persist", "vmpool/persist"),
        ]:
            got = machine.succeed(f"findmnt -no SOURCE,FSTYPE {path}").split()
            assert got == [source, "zfs"], f"{path} is {got}, expected [{source}, zfs]"

    with subtest("/boot is a plain FAT ESP reached by label"):
        # Note what this does *not* claim: it is not AWS-specific.
        # cogitator/nixos/sarcophagus-kvm.nix:114 declares a byte-identical
        # /boot. The two cogitators each carry their own copy of the
        # declaration, which is exactly why this belongs here — a regression in
        # the AWS copy would not be caught by the KVM proving, and vice versa.
        #
        # The image is BIOS/GRUB, and the ESP carries no EFI role: it is a plain
        # FAT /boot. The three-partition layout it sits in — bios_grub(1),
        # ESP(2), ZFS(3) — is what makes relics-aws default ebsPartition = 3. The
        # partition *numbering* is nixpkgs', so it is not asserted here; what is
        # asserted is the mount the cogitator declares.
        #
        # Two readings, because findmnt reports the kernel device node and not
        # the path the cogitator declares — measured, it answers /dev/vda2.
        #
        # Be clear about what the second reading is and is not. It is *not* a
        # guard against the declaration drifting: if the cogitator ever named
        # /dev/vda2 directly, both sides would still answer /dev/vda2 and this
        # would stay green. Conditional on /boot being mounted at all, the label
        # resolving to the mounted device is close to implied. What it does check
        # is that udev's label index still carries ESP pointing at that device —
        # the discriminating work is done by the first reading, since a bare node
        # has no vfat /boot mount for findmnt to find.
        source = machine.succeed("findmnt -no SOURCE /boot").strip()
        fstype = machine.succeed("findmnt -no FSTYPE /boot").strip()
        assert fstype == "vfat", f"/boot is {fstype}, expected vfat"
        by_label = machine.succeed("readlink -f /dev/disk/by-label/ESP").strip()
        assert by_label == source, (
            f"/boot is mounted from {source}, but the ESP label resolves to "
            f"{by_label} — the declaration and the mount have diverged"
        )

    with subtest("the pool grew to fill the volume under it"):
        # The claim no other proving in this suite can reach.
        #
        # Two readings, not one. The unit's journal says the growth path ran to
        # completion; the pool size says it had an effect. Either alone could be
        # green for the wrong reason — a no-op growpart still exits 1, which the
        # relic deliberately tolerates, so "the unit succeeded" does not by
        # itself mean anything grew.
        # What this pair isolates, and what it does not. A regression that stops
        # the partition from growing turns it red: the growth is visible in the
        # unit's own log ("CHANGED: partition=3 ... new: size=14680031") and
        # without it the pool stays under the threshold. The script's *second*
        # half is less well isolated — upstream builds this pool with
        # `rootPoolProperties = { autoexpand = "on"; }`, so a broken
        # `zpool online -e` might be masked by autoexpand reacting to growpart.
        # Upstream's own header argues it would not be ("This single-disk
        # approach does not satisfy ZFS's requirements for autoexpand"), but that
        # is an unmeasured premise: checking it means editing the relic, which
        # forces a fresh in-VM image build. Said out loud rather than implied.
        journal = machine.succeed("journalctl -b -u stc-grow-pool --no-pager")
        assert "Finished" in journal, f"stc-grow-pool did not succeed:\n{journal}"

        size = int(machine.succeed("zpool list -Hpo size vmpool").strip())
        # Logged, not only asserted: the threshold below is a floor, and a run
        # that barely clears it means something changed about the bench.
        print(f"vmpool size after growth: {size} bytes ({size / 1024**3:.2f} GiB)")
        # The threshold is anchored on the *pool*, which is the quantity read
        # above — not on the image file, which is 5 GiB and would leave this
        # threshold no clearance at all on that side.
        #
        # Measured on the artefact and on the bench: p3 backs the pool and is
        # 8386560 sectors = 3.999 GiB un-grown, and the pool comes up at
        # 7247757312 bytes = 6.75 GiB grown. So 5 GiB sits ~1 GiB above the
        # un-grown size and ~1.75 GiB below the grown one. Without the relic
        # there is no growth unit at all and the pool would stay at p3's ~4 GiB,
        # so this assertion discriminates by construction.
        assert size > 5 * 1024**3, (
            f"pool is {size} bytes (~{size / 1024**3:.1f} GiB) — it did not grow "
            "past the ZFS partition it was built on"
        )

    with subtest("the two discriminating AWS kernel parameters are live"):
        # Measured on a bare node: neither is present, while console=ttyS0 is.
        # Those two are the only kernel parameters of the relic that tell it
        # apart from the test socle — see the header on the baud rate.
        cmdline = machine.succeed("cat /proc/cmdline")
        for param in ["nvme_core.io_timeout=4294967295", "random.trust_cpu=on"]:
            assert param in cmdline, f"{param} missing from {cmdline!r}"

    with subtest("both instance classes' network drivers are asked for, and"
                 " asking for the wrong one is free"):
        # boot.kernelModules = ["ena" "xen_netfront"] in the relic: the Nitro
        # driver and the Xen one, because one image serves both instance
        # classes. Measured on a bare node, kernelModules is ["atkbd" "loop"] —
        # neither is there without the relic.
        #
        # What the bench taught, and what makes this subtest worth its lines:
        # `ena` inserts fine on KVM (it is an ordinary PCI driver and simply
        # finds no device), while `xen_netfront` *cannot* — measured,
        # `modprobe` answers "could not insert 'xen_netfront': No such device",
        # because there is no Xen paravirt bus to attach to. systemd-modules-load
        # logs "Failed to insert module 'xen_netfront'" and **finishes
        # successfully anyway**, which is why the boot above is `running` and not
        # `degraded`.
        #
        # That tolerance is the property under test, not an accident: it is what
        # lets a single AMI boot on Nitro *and* on Xen. It would break if the
        # relic ever moved these into boot.initrd.kernelModules, or if something
        # made modules-load strict — and then the image would fail to boot on
        # whichever instance class it is not running on. So the assertions are
        # "both are requested", "the one that can load did", and "the unit is
        # green regardless" — deliberately not "both are loaded", which is only
        # ever true on hardware this bench cannot be.
        requested = machine.succeed("cat /etc/modules-load.d/nixos.conf").split()
        for mod in ["ena", "xen_netfront"]:
            assert mod in requested, f"{mod} is not requested in modules-load.d"

        loaded = machine.succeed("lsmod").split()
        assert "ena" in loaded, "the Nitro driver did not load"

        assert machine.succeed(
            "systemctl is-active systemd-modules-load"
        ).strip() == "active", (
            "systemd-modules-load is not green — a module that cannot insert on "
            "this instance class must not fail the boot"
        )

    with subtest("xen_fbfront is blacklisted"):
        # The relic blacklists it because it costs a 30-second boot delay on Xen
        # instances. Measured: a bare node blacklists nothing at all.
        #
        # modprobe canonicalises module names (dashes become underscores), so
        # both sides are normalised before comparison — the gotcha found while
        # writing the hardening proving's module subtest.
        config = machine.succeed("modprobe --showconfig").replace("-", "_")
        assert "blacklist xen_fbfront" in config, (
            "xen_fbfront is not blacklisted in the effective modprobe config"
        )

    with subtest("the EC2 udev rules are installed"):
        # services.udev.packages = [pkgs.amazon-ec2-utils] in the relic: these
        # rules are what give EBS volumes their EC2 device names. Measured on a
        # bare node: amazon-ec2-utils is not among the udev packages, so the file
        # is absent. The NVMe rule is named rather than globbed so that a package
        # reorganisation upstream shows up as a red test and not a silent pass.
        machine.succeed("test -e /etc/udev/rules.d/70-ec2-nvme-devices.rules")
  '';
}
