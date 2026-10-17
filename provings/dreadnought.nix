# Proving: dreadnought cogitator
# Boots the EC2 running-system profile — ZFS, networking, impermanence, the AWS
# platform and the full hardening suite composed into one — and asserts the parts
# of that composition a VM can actually observe.
#
# The central claim is the boot itself: five relics stacked on one host, one of
# them rolling the root dataset back from the initrd. That the result comes up is
# not a formality.
#
# ---------------------------------------------------------------------------
# Scope note — what a nixosTest cannot see here, and why. This is the longest
# such note in the suite, because this profile is the one that owns disks.
#
# The qemu-vm module replaces whole option sets at priority 10, which *wins*
# against everything a relic can write (mkForce is 50, a plain definition 100).
# That is the default, not a law: `virtualisation.fileSystems = lib.mkForce {}`
# opts out of it, and provings/sarcophagus-kvm.nix uses exactly that to boot a
# real image and assert the disk layer. It is not done here because this profile
# targets an AMI, and the AMI's disk is EBS — see the closing paragraph.
# Measured on this very node, as it stands:
#
#   - `fileSystems` becomes the VM's own set — "/", "/nix/.ro-store",
#     "/nix/.rw-store", "/nix/store", "/tmp/shared", "/tmp/xchg". The profile's
#     ZFS mounts for "/", "/nix" and "/persist" are not there, so pool import and
#     dataset mounting cannot be asserted. (The impermanence *bind* mounts are a
#     different mechanism and they ARE asserted — see the subtest below.)
#   - `boot.loader.grub.device` becomes "/dev/disk/by-id/virtio-root", so the EBS
#     disk the profile points GRUB at is not observable either.
#   - `services.timesyncd` is off in the test socle, so the AWS relic's NTP
#     endpoint (169.254.169.123) renders nowhere. The networking relic's two
#     claims are equally invisible: there is no /etc/resolv.conf in the node, so
#     the Quad9 resolvers cannot be read, and `usePredictableInterfaceNames` is
#     `false` here — the relic sets it with mkDefault, so it simply loses an
#     ordinary priority contest against the socle rather than being forced.
#   - `serial-getty@ttyS0` is claimed by the test instrumentation, which owns
#     that port. The relic now defines it with mkDefault precisely so this node
#     can boot at all, which means the getty is *off* here.
#   - Following from that: **the AWS serial-console claim has no coverage in this
#     proving at all.** The getty is off, and `console=ttyS0,115200n8` is not
#     usable as a proxy either — measured, the test socle sets
#     `virtualisation.qemu.consoles = ["ttyS0,115200n8" "tty0"]` on a *bare* node,
#     so that exact string appears on the kernel command line whatever the relic
#     does. Only the other two AWS kernel parameters discriminate.
#
# What the boot does establish: the initrd rollback unit runs, fails for want of
# a pool, and the boot continues anyway — the unit is pulled by Wants, not
# Requires. The booted system is therefore `degraded`, with exactly one failed
# unit that is loaded in the booted system, and the subtest below pins that set.
#
# None of the unobservable parts is a code problem. Two benches cover the disk
# layer instead: provings/sarcophagus-kvm.nix, which boots a built qcow2 under
# the test driver and asserts the pool, the datasets and the rollback; and the
# local-vm qcow2 booted by hand (`just build` + `just run` + `just ssh`), which
# is what proved the ZFS import change in v0.13.0. A proving that pretended to
# cover disks would be worse than one that says where to look.
#
# Also deliberately not asserted:
#
#   - `services.udisks2.enable = false`, which the AWS relic sets to keep GTK off
#     a headless server. Measured false on a bare nixosTest node too, so the
#     assertion could not tell the relic from the default.
#   - `stc.relics.zfs.kernel`. The relic pins an LTS kernel (6.12.111 here) and
#     the option can select "latest" instead, but pinning `uname -r` in an
#     assertion would go red on every nixpkgs bump, for no product reason.
#     Measured: a node with only `boot.supportedFilesystems = ["zfs"]` runs
#     6.18.53 *and* gets a working ZFS module, so loading the module proves ZFS
#     support is functional — not that the pin is the one the relic chose.
# ---------------------------------------------------------------------------
{self}: {
  name = "dreadnought";

  nodes.machine = {
    imports = [self.nixosModules.cogitator-dreadnought];

    stc.cogitator.dreadnought = {
      enable = true;

      # Moved off its default so the persistence subtest proves the option
      # threads end to end, instead of only proving the relic's own built-in
      # list. Measured: this lands as a systemd bind mount, which the qemu-vm
      # module does not touch.
      impermanence.extraDirectories = ["/var/lib/stc-proving"];
    };

    # Required by the ZFS relic's upstream assertion ("ZFS requires
    # networking.hostId to be set"), exactly as the three schematics set it. The
    # value is arbitrary here: nothing imports a pool in this VM.
    networking.hostId = "deadbeef";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    with subtest("the profile boots, and only the pool-dependent unit fails"):
        # The claim of the issue, and the one thing no eval can establish: five
        # relics on one host, including an initrd service that tries to roll back
        # a dataset that does not exist in this VM.
        #
        # --wait, because multi-user.target being active does not mean systemd
        # has finished starting up; `|| true` because the honest answer here is
        # `degraded` and that exits non-zero.
        state = machine.succeed("systemctl is-system-running --wait || true").strip()
        assert state == "degraded", f"unexpected system state: {state}"

        # Pinned, not bounded, and the second column is why. zfs-rollback exists
        # only in the initrd — measured, it has no fragment in the booted system
        # (LoadState=not-found) — so whether its failure is still listed after
        # switch-root varies between runs. Filtering on "loaded" drops that
        # non-determinism without widening what the assertion accepts: a real
        # booted-system unit failing, whatever its name, still turns this red.
        failed = machine.succeed(
            "systemctl list-units --state=failed --plain --no-legend --all"
        )
        failed_units = {
            line.split()[0]
            for line in failed.splitlines()
            if line.strip() and line.split()[1] == "loaded"
        }
        assert failed_units == {"stc-grow-pool.service"}, (
            f"unexpected failed units: {failed_units}"
        )

    with subtest("ZFS support is functional on the booted kernel"):
        # What this proves is in its name, and no more — see the scope note on
        # why the kernel *pin* is not asserted.
        machine.succeed("modprobe zfs")
        machine.succeed("zpool status")

    with subtest("the AWS platform parameters reach the running kernel"):
        cmdline = machine.succeed("cat /proc/cmdline")
        # These two, and deliberately not console=ttyS0,115200n8: the socle sets
        # that one itself on a bare node, so it would be green whatever the relic
        # did. Both of these are absent on a bare node, measured.
        for param in ["nvme_core.io_timeout=4294967295", "random.trust_cpu=on"]:
            assert param in cmdline, f"{param} missing from:\n{cmdline}"

    with subtest("the pool-growth unit carries the profile's own values"):
        # Reading the unit and throwing the output away would prove only that a
        # file exists. The rendered script is where three cogitator options and
        # one computation land, so it is what gets read.
        unit = machine.succeed("systemctl cat stc-grow-pool.service")
        exec_start = [
            line.split("=", 1)[1].strip()
            for line in unit.splitlines()
            if line.startswith("ExecStart=")
        ]
        assert len(exec_start) == 1, f"expected one ExecStart, got {exec_start}"
        script = machine.succeed(f"cat {exec_start[0].split()[0]}")

        # ebsDisk + ebsPartition, as growpart receives them.
        assert "growpart /dev/nvme0n1 3" in script, f"unexpected growpart call:\n{script}"
        # poolName, plus the partSep rule from the relic: the "p" is inserted
        # only because the device name ends in a digit. A module that got that
        # backwards would render /dev/nvme0n13 and still pass a bare file check.
        assert "zpool online -e vmpool /dev/nvme0n1p3" in script, (
            f"unexpected zpool call:\n{script}"
        )

    with subtest("the ZFS relic's own maintenance timer is installed"):
        # zfs-scrub and not zpool-trim: measured, services.zfs.trim.enable is
        # already true upstream, so the trim timer exists with no STC relic at
        # all. The scrub timer is absent without the relic, and it carries an
        # option value — stc.relics.zfs.scrubInterval, "monthly" by default.
        timer = machine.succeed("systemctl cat zfs-scrub.timer")
        assert "OnCalendar=monthly" in timer, f"unexpected scrub schedule:\n{timer}"

    with subtest("explicit persistence is wired, including the profile's own entry"):
        # The impermanence relic's whole contract is "if it's not listed, it's
        # gone". That is NOT delivered through fileSystems — it is a set of
        # systemd bind mounts, which the qemu-vm module leaves alone — so unlike
        # the dataset mounts it is observable here.
        for path in ["/var/log", "/var/lib/nixos"]:
            machine.succeed(f"findmnt --target {path}")

        # The host identity files the relic keeps across a rollback. machine-id
        # is the one whose loss breaks journald.
        # machine-id is the entry whose loss breaks journald, and it is the one
        # file-level bind mount that does materialise here.
        machine.succeed("findmnt /etc/machine-id")

        # NOT asserted here, and no longer an open question. The four
        # /etc/ssh/ssh_host_* entries the relic also declares have no mount unit
        # at all, and the reason is upstream: impermanence renders `files`
        # through mount-file.bash, which bind-mounts when the target exists and
        # *symlinks* when it does not. /etc/machine-id takes a special branch
        # that always bind-mounts, hence the asymmetry above.
        #
        # provings/sarcophagus-kvm.nix settled what that means on a real host,
        # and the answer is not the obvious one. The symlinks are written by the
        # `persist-files` activation script during the *image build*, so they
        # are inside @blank; every rollback restores them, mount-file.bash sees
        # a link already pointing at its target and does nothing, and sshd reads
        # the key through it from /persist. Measured there: the host key
        # fingerprint is identical either side of a rollback. A sarcophagus does
        # not change its host keys on reboot.

        # And the cogitator's own option, set on this node: without it threading
        # through to the relic, this mount would not exist.
        machine.succeed("findmnt --target /var/lib/stc-proving")

    with subtest("the hardening suite traverses the profile"):
        # Two probes, not the whole matrix — the hardening proving owns that.
        # What is proven here is that composing five relics does not drop it.
        # Measured on a bare node: kptr_restrict is 1 and PermitRootLogin is
        # prohibit-password, so both values below are this profile's doing.
        assert machine.succeed("sysctl -n kernel.kptr_restrict").strip() == "2"
        sshd_config = machine.succeed("sshd -T").lower()
        assert "permitrootlogin no" in sshd_config, "root login is not refused"

    with subtest("the impermanence rollback ran in the initrd, and failed as expected"):
        # Queried by unit rather than grepped out of the whole journal: the unit
        # has no fragment in the booted system, but its initrd journal entries
        # carry _SYSTEMD_UNIT, so -u resolves them. Grepping the description
        # string instead would go red if someone reworded the relic, and would
        # embed the default poolName.
        journal = machine.succeed("journalctl -b -u zfs-rollback.service --no-pager")
        assert "zfs-rollback" in journal, "the rollback unit left no journal trace"
        # It fails here, and that is the expected outcome — there is no vmpool to
        # roll back. Asserting the failure is what proves the unit actually ran
        # rather than being skipped: a unit that never started logs nothing.
        assert "Failed" in journal or "failed" in journal, (
            f"the rollback unit did not run to a failure:\n{journal}"
        )
  '';
}
