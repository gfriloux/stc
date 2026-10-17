# Proving: dreadnought cogitator
# Boots the EC2 running-system profile — ZFS, networking, impermanence, the AWS
# platform and the full hardening suite composed into one — and asserts the parts
# of that composition a VM can actually observe.
#
# The central claim is the boot itself: five relics stacked on one host, one of
# them replacing the root filesystem and one of them rolling it back from the
# initrd. That the result comes up is not a formality.
#
# ---------------------------------------------------------------------------
# Scope note — what a nixosTest cannot see here, and why. This is the longest
# such note in the suite, because this profile is the one that owns disks.
#
# The qemu-vm module replaces whole option sets, at a priority the relics cannot
# reach (mkVMOverride is priority 10; even mkForce is 50). Measured on this very
# node:
#
#   - `fileSystems` becomes the VM's own set — "/", "/nix/.ro-store",
#     "/nix/.rw-store", "/nix/store", "/tmp/shared", "/tmp/xchg". The profile's
#     ZFS mounts for "/", "/nix" and "/persist" are simply not there, so pool
#     import and dataset mounting cannot be asserted.
#   - `boot.loader.grub.device` becomes "/dev/disk/by-id/virtio-root", so the
#     EBS disk the profile points GRUB at is not observable either.
#   - `services.timesyncd` is off in the test socle, so the AWS NTP endpoint
#     (169.254.169.123) renders nowhere, and `usePredictableInterfaceNames` is
#     forced back to false — the networking relic's two visible claims are both
#     out of reach.
#   - `serial-getty@ttyS0` is claimed by the test instrumentation, which owns
#     that port. The relic now defines it with mkDefault precisely so this node
#     can boot at all, which means the getty is *off* here and cannot be
#     asserted on.
#
# What the boot does establish, measured: the initrd rollback unit runs, fails
# for want of a pool, and the boot continues anyway — the unit is pulled by
# Wants, not Requires. The booted system is `degraded` with exactly one failed
# unit, stc-grow-pool.service, which also needs the pool. Both are asserted by
# name below rather than tolerated silently.
#
# None of the unobservable parts is a code problem, and none of them is asserted
# below. The real bench for the disk layer is the local-vm qcow2 image booted by
# hand (`just build` + `just run` + `just ssh`), which is what proved the ZFS
# import change in v0.13.0. A proving that pretended to cover disks would be
# worse than one that says where to look.
#
# Also deliberately not asserted: `services.udisks2.enable = false`, which the
# AWS relic sets to keep GTK off a headless server. Measured false on a bare
# nixosTest node too, so the assertion could not tell the relic from the default.
# ---------------------------------------------------------------------------
{self}: {
  name = "dreadnought";

  nodes.machine = {
    imports = [self.nixosModules.cogitator-dreadnought];
    stc.cogitator.dreadnought.enable = true;

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
        # The system is `degraded`, not `running`, which is the honest outcome
        # here: one unit needs a pool to do anything. Naming the expected set is
        # what makes this an assertion rather than a shrug — any *other* unit
        # failing is a regression this subtest must catch.
        state = machine.succeed("systemctl is-system-running || true").strip()
        assert state == "degraded", f"unexpected system state: {state}"

        failed = machine.succeed(
            "systemctl list-units --state=failed --plain --no-legend --all"
        )
        failed_units = {line.split()[0] for line in failed.splitlines() if line.strip()}

        # Bounded, not pinned. Both units below need the pool: stc-grow-pool is
        # always listed, while zfs-rollback ran in the *initrd* and whether its
        # failure is still carried in the booted system's state after switch-root
        # was observed both ways across runs of this same configuration. Pinning
        # the set would make this subtest flaky for a systemd-internal reason;
        # bounding it still catches the regression that matters, which is any
        # other unit failing.
        pool_dependent = {"stc-grow-pool.service", "zfs-rollback.service"}
        unexpected = failed_units - pool_dependent
        assert not unexpected, f"unexpected failed units: {unexpected}"
        assert "stc-grow-pool.service" in failed_units, (
            f"stc-grow-pool.service should have failed without a pool: {failed_units}"
        )

    with subtest("the ZFS-capable kernel really runs"):
        # The ZFS relic pins a kernel it knows has a working module; a bare test
        # node runs a newer one with no zfs module at all. Loading it is what
        # separates "the relic pinned something" from "the pin boots".
        machine.succeed("modprobe zfs")
        machine.succeed("zpool status")
        machine.succeed("zfs --version")

    with subtest("the AWS platform parameters reach the running kernel"):
        cmdline = machine.succeed("cat /proc/cmdline")
        # The baud rate is what discriminates: the test socle passes a bare
        # `console=ttyS0` of its own, so matching on that alone would prove
        # nothing. These three are the AWS relic's.
        for param in [
            "console=ttyS0,115200n8",
            "nvme_core.io_timeout=4294967295",
            "random.trust_cpu=on",
        ]:
            assert param in cmdline, f"{param} missing from:\n{cmdline}"

    with subtest("the AWS and ZFS maintenance units are installed"):
        # stc-grow-pool is how an instance takes the extra space after an EBS
        # volume is resized. systemctl cat reads it from disk, which is the
        # point: it cannot usefully run without a pool, and the subtest above
        # already accounts for its failure.
        machine.succeed("systemctl cat stc-grow-pool.service")
        machine.succeed("systemctl cat zpool-trim.timer")

    with subtest("the hardening suite traverses the profile"):
        # Two probes, not the whole matrix — the hardening proving owns that.
        # What is proven here is that composing five relics does not drop it.
        # kptr_restrict is 1 on a bare test node, so 2 is this profile's doing.
        assert machine.succeed("sysctl -n kernel.kptr_restrict").strip() == "2"
        sshd_config = machine.succeed("sshd -T").lower()
        assert "permitrootlogin no" in sshd_config, "root login is not refused"

    with subtest("the impermanence rollback is wired into the initrd"):
        # What is checkable: the unit ran in the initrd and its journal survived
        # the switch-root into the booted system. It fails there — there is no
        # vmpool to roll back — so what this asserts is the wiring and the
        # ordering, not the rollback itself. The rollback behaviour belongs to
        # the local-vm bench named in the scope note above.
        journal = machine.succeed("journalctl -b --no-pager")
        assert "Rollback vmpool/root to @blank" in journal, (
            "the zfs-rollback initrd unit never ran"
        )
  '';
}
