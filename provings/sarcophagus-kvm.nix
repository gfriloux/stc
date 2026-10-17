# Proving: sarcophagus-kvm cogitator
# Builds the qcow2 disk image the profile exists to produce, boots it twice on
# the same disk, and asserts the one claim no other proving in this suite can
# reach: the root dataset is really rolled back to @blank between the two boots,
# and only /persist survives it.
#
# ---------------------------------------------------------------------------
# Why this proving does not look like the other seven.
#
# The other provings let the test driver synthesise a node. That is enough for a
# profile that configures services, and it is not enough here: this profile's
# claim *is* the disk. Measured on a standard node, the qemu-vm module replaces
# `fileSystems` with its own set at priority 10 (mkVMOverride), which beats
# anything a relic can write — see the scope note in provings/dreadnought.nix.
# Neither the pool, nor the datasets, nor the rollback would be observable.
#
# So this one follows nixpkgs' own nixos/tests/qemu-vm-external-disk-image.nix:
# the node declares the image, the test driver boots *that image* instead of
# synthesising a root. Five lines make it work, and each one is a concession to
# the bench rather than a product fix — the upstream module exposes every one of
# them on purpose:
#
#   virtualisation.directBoot.enable = false   boot the image's own GRUB
#   virtualisation.mountHostNixStore = false   the store lives in the image
#   virtualisation.fileSystems = mkForce {}    stop the qemu-vm override, so the
#                                              profile's ZFS mounts survive
#   virtualisation.bootLoaderDevice = "/dev/vda"
#                                              measured: qemu-vm.nix pins
#                                              boot.loader.grub.device to
#                                              /dev/disk/by-id/virtio-root at
#                                              priority 10, which beats the
#                                              cogitator's own mkForce, and the
#                                              image builder then installs GRUB
#                                              on a device that is not there
#   system.switch.enable = true                measured: nixos-test-base.nix
#                                              defaults it off, and nixos-install
#                                              inside the image builder needs
#                                              switch-to-configuration
#
# #47 (sarcophagus-aws) can reuse this pattern as-is; it is the reason the five
# lines are commented individually rather than as a block.
#
# ---------------------------------------------------------------------------
# Deliberately not asserted:
#
#   - the partition layout (bios_grub + ESP + ZFS). It is produced by
#     make-single-disk-zfs-image.nix, so asserting it would measure nixpkgs
#     rather than STC.
#   - the rollback's *failure* path. Destroying @blank between two boots to watch
#     the machine refuse to come up would test systemd, not this relic. What is
#     asserted instead is that the nominal path stays clean — which is the thing
#     a change to the relic can actually break.
# ---------------------------------------------------------------------------
{self}: {
  name = "sarcophagus-kvm";

  nodes.machine = {lib, ...}: {
    imports = [self.nixosModules.cogitator-sarcophagus-kvm];

    stc.cogitator.sarcophagus-kvm = {
      enable = true;

      # Moved off its default so the persistence subtest proves the cogitator
      # option threads all the way into the relic, instead of only proving the
      # relic's own built-in list.
      impermanence.extraDirectories = ["/var/lib/stc-proving"];
    };

    # Required by the ZFS relic's upstream assertion, exactly as the three
    # schematics set it. Unlike the dreadnought node, this one imports a real
    # pool, so the value is load-bearing for the import.
    networking.hostId = "deadbeef";

    # The five bench concessions — see the header for what each one measured.
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
    # delete=False and a single creation are both load-bearing: this file is the
    # disk across *both* boots, and the whole proving rests on it keeping its
    # writes between them.
    overlay = tempfile.NamedTemporaryFile(suffix=".qcow2", delete=False)
    subprocess.run(
        [
            "${nodes.machine.virtualisation.qemu.package}/bin/qemu-img",
            "create", "-f", "qcow2",
            "-b", "${nodes.machine.system.build.qcow2}/nixos.root.qcow2",
            "-F", "qcow2",
            overlay.name,
        ],
        check=True,
    )
    os.environ["NIX_DISK_IMAGE"] = overlay.name

    ROOT_WITNESS = "/stc-proving-witness-root"
    PERSIST_WITNESS = "/persist/stc-proving-witness-persist"
    OPTION_WITNESS = "/var/lib/stc-proving/witness"

    machine.start()
    machine.wait_for_unit("multi-user.target")

    with subtest("boot 1: the image comes up with nothing failing"):
        # `running`, not `degraded`, and that is the whole point of booting the
        # real image: the dreadnought node is degraded because it has no pool to
        # roll back. Here the pool exists, so every unit of the profile must be
        # satisfied. A regression that leaves any unit failing turns this red.
        state = machine.succeed("systemctl is-system-running --wait || true").strip()
        assert state == "running", f"unexpected system state: {state}"

    with subtest("boot 1: the profile's own ZFS datasets are what is mounted"):
        # SOURCE and FSTYPE, not merely "/ is mounted" — with the qemu-vm
        # override back in place this would be the driver's own disk and a bare
        # mount check would still pass.
        for path, source in [
            ("/", "vmpool/root"),
            ("/nix", "vmpool/nix"),
            ("/persist", "vmpool/persist"),
        ]:
            got = machine.succeed(f"findmnt -no SOURCE,FSTYPE {path}").split()
            assert got == [source, "zfs"], f"{path} is {got}, expected [{source}, zfs]"

    with subtest("boot 1: the relic created the @blank reference itself"):
        # Measured: make-single-disk-zfs-image.nix creates no snapshot at all
        # (no `zfs snapshot` anywhere in it), so this one exists only because the
        # relic's initrd script took it on this very boot. Without the relic,
        # there is no @blank and the next subtest could not mean anything.
        snapshots = machine.succeed("zfs list -t snapshot -H -o name")
        assert "vmpool/root@blank" in snapshots.split(), (
            f"@blank was not created:\n{snapshots}"
        )

    with subtest("boot 1: the rollback unit ran in the initrd and succeeded"):
        # The nominal path. provings/dreadnought.nix can only observe this unit
        # failing, for want of a pool; this is the first place in the suite where
        # it is seen doing its job.
        journal = machine.succeed("journalctl -b -u zfs-rollback.service --no-pager")
        assert "Finished" in journal, f"the rollback unit did not succeed:\n{journal}"

    with subtest("boot 1: the SSH host keys live in the persistent dataset"):
        # Settles the question provings/dreadnought.nix left open in writing.
        #
        # Upstream impermanence renders `files` through mount-file.bash, which
        # bind-mounts when the target already exists and *symlinks* when it does
        # not. It runs that script twice over: once as a persist-*.service unit,
        # and once as the `persist-files` activation script (nixos.nix:477) —
        # and the activation script is what nixos-install runs inside the image
        # builder, where /persist is still empty. So the four symlinks are baked
        # into the image, not created at runtime. Measured below and on boot 2.
        target = machine.succeed(
            "readlink -f /etc/ssh/ssh_host_ed25519_key"
        ).strip()
        assert target == "/persist/etc/ssh/ssh_host_ed25519_key", (
            f"host key resolves to {target}, not into the persistent dataset"
        )
        # The symlink is only a legitimate mechanism if the target became real:
        # sshd-keygen wrote the key *through* it, into the persistent dataset.
        machine.succeed(f"test -s {target}")

    # Three witnesses, written *after* @blank was taken, so none of them is in
    # the snapshot. One on the root dataset, one in /persist, and one under the
    # path declared through the cogitator's own extraDirectories option.
    machine.succeed(f"echo written-on-boot-1 > {ROOT_WITNESS}")
    machine.succeed(f"echo written-on-boot-1 > {PERSIST_WITNESS}")
    machine.succeed(f"echo written-on-boot-1 > {OPTION_WITNESS}")

    fingerprint_before = machine.succeed(
        "ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub"
    ).split()[1]

    machine.shutdown()
    machine.start()
    machine.wait_for_unit("multi-user.target")

    with subtest("boot 2: the root dataset forgot, and /persist remembered"):
        # The relic's header sentence, made checkable. The first assertion is the
        # impermanence claim; the second and third are what stops this proving
        # from being green for the wrong reason — if the overlay were recreated
        # between boots rather than rolled back, the root witness would also be
        # gone, and only these two would notice.
        machine.fail(f"test -e {ROOT_WITNESS}")
        assert machine.succeed(f"cat {PERSIST_WITNESS}").strip() == "written-on-boot-1"
        assert machine.succeed(f"cat {OPTION_WITNESS}").strip() == "written-on-boot-1"

    with subtest("boot 2: the host identity survived the rollback"):
        # If this changed, every reboot of a sarcophagus would break its clients'
        # known_hosts — the concrete consequence named in dreadnought's open
        # question.
        fingerprint_after = machine.succeed(
            "ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub"
        ).split()[1]
        assert fingerprint_after == fingerprint_before, (
            f"host key changed across the rollback: "
            f"{fingerprint_before} -> {fingerprint_after}"
        )
        machine.succeed("findmnt /etc/machine-id")

    with subtest("boot 2: and here is why the host key survives at all"):
        # The fingerprint assert above says *that* it survives; this one says
        # why, because the obvious explanation is wrong and was measured wrong.
        #
        # It is tempting to reason that the rollback wipes boot 1's symlinks, so
        # mount-file.bash re-runs, now finds a real file in /persist, and
        # bind-mounts it. That is not what happens. The symlinks were written by
        # the activation script *during the image build*, so they are already in
        # the root dataset when the initrd takes @blank — and the rollback
        # therefore restores them. mount-file.bash then hits its first branch
        # ("already links to target, ignoring") and does nothing at all.
        #
        # Measured: @blank carries the symlink, /etc/ssh is still a symlink and
        # has no mount, and the persist-* units are green having done nothing.
        machine.succeed("test -L /etc/ssh/ssh_host_ed25519_key")
        assert machine.succeed(
            "findmnt /etc/ssh/ssh_host_ed25519_key || echo NO-MOUNT"
        ).strip().endswith("NO-MOUNT"), "expected a symlink, not a bind mount"

        machine.succeed("mkdir -p /mnt/blank")
        machine.succeed("mount -t zfs -o ro vmpool/root@blank /mnt/blank")
        in_blank = machine.succeed(
            "readlink /mnt/blank/etc/ssh/ssh_host_ed25519_key"
        ).strip()
        machine.succeed("umount /mnt/blank")
        assert in_blank == "/persist/etc/ssh/ssh_host_ed25519_key", (
            f"@blank does not carry the host-key symlink, it carries {in_blank!r} "
            "— the mechanism described above no longer holds"
        )

    with subtest("boot 2: the rollback ran again on a @blank it did not recreate"):
        # The second boot takes the *existing* snapshot path, which is the branch
        # a real host runs for the rest of its life. It must not create anything.
        journal = machine.succeed("journalctl -b -u zfs-rollback.service --no-pager")
        assert "Finished" in journal, f"the rollback unit did not succeed:\n{journal}"
        state = machine.succeed("systemctl is-system-running --wait || true").strip()
        assert state == "running", f"unexpected system state on boot 2: {state}"
  '';
}
