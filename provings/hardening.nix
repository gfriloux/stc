# Proving: hardening cogitator
# Boots a VM with stc.cogitator.hardening enabled and asserts the hardening is
# actually in effect at runtime — not merely that the module evaluates.
#
# Scope note — filesystem mount hardening is NOT asserted here. The relic
# delivers it through `fileSystems` ("/tmp"+"/dev/shm" noexec, "/proc" hidepid=2),
# but the nixosTest qemu-vm module replaces the entire `fileSystems` set with
# `mkVMOverride` (priority 10), which overrides the relic's `mkForce` (priority
# 50). Those mounts therefore never exist inside the test VM, so a runtime check
# would fail for framework reasons, not real ones. sysctl-based hardening
# (kernel, network) is unaffected and IS asserted below. The /var/tmp mount
# (#40) is asserted in provings/sarcophagus-kvm.nix, which boots a real image.
{self}: {
  name = "hardening";

  nodes.machine = {pkgs, ...}: let
    # Snakeoil keypair shipped with nixpkgs' own test suite.
    sshKeys = import (pkgs.path + "/nixos/tests/ssh-keys.nix") pkgs;
  in {
    imports = [self.nixosModules.cogitator-hardening];
    stc.cogitator.hardening.enable = true;

    # The banner is opt-in and defaults to null, so the test node has to set it
    # for the subtest below to have anything to assert.
    stc.relics.hardening.ssh.banner = "Authorized access only. All activity is logged.\n";

    # Same reason: RA rejection is opt-in, so the node turns it on to make the
    # sysctl assertion below meaningful. Safe here — the test VM's networking is
    # statically configured by the test driver, it never relies on SLAAC.
    stc.relics.hardening.network.strictIpv6RouterAdvertisements = true;

    # relics.hardening.scheduler is inert unless a scheduler actually runs — its
    # whole config is guarded by mkIf services.<x>.enable. STC enables neither
    # (it schedules with systemd timers), so the node has to turn both on for the
    # allowlist assertions to prove anything.
    services.cron.enable = true;
    services.atd.enable = true;

    # An unprivileged user to prove the restriction from the outside: root is on
    # the allowlist, so only a normal user can show that the gate closes.
    users.users.schedtest = {
      isNormalUser = true;
      description = "unprivileged user for the scheduler allowlist subtest";
    };

    # Two users, one key. "declared" receives it through the module, "homedir"
    # gets the very same public key planted in ~/.ssh by hand. Using a single
    # keypair for both is deliberate: with two, the negative assertion could
    # pass because an algorithm was refused rather than because a path was, and
    # a test that passes for the wrong reason is worse than no test at all.
    users.users.declared = {
      isNormalUser = true;
      description = "key declared in the flake - authentication must succeed";
      openssh.authorizedKeys.keys = [sshKeys.snakeOilEd25519PublicKey];
    };

    users.users.homedir = {
      isNormalUser = true;
      description = "key planted in ~/.ssh - authentication must fail";
    };

    # Copied out of the store at 0600: ssh refuses a private key others can
    # read, and every store path is world-readable.
    environment.etc."proving-ssh-key" = {
      source = sshKeys.snakeOilEd25519PrivateKey;
      mode = "0600";
    };
  };

  testScript = {nodes, ...}: ''
    machine.wait_for_unit("multi-user.target")

    with subtest("kernel sysctl hardening"):
        assert machine.succeed("sysctl -n kernel.kptr_restrict").strip() == "2"
        assert machine.succeed("sysctl -n kernel.randomize_va_space").strip() == "2"
        assert machine.succeed("sysctl -n kernel.unprivileged_bpf_disabled").strip() == "1"
        assert machine.succeed("sysctl -n kernel.yama.ptrace_scope").strip() == "1"
        assert machine.succeed("sysctl -n fs.suid_dumpable").strip() == "0"
        assert machine.succeed("sysctl -n kernel.panic_on_oops").strip() == "1"
        # The test framework puts panic=1 on the kernel command line
        # (nixos/modules/testing/test-instrumentation.nix), so this also proves
        # the relic's sysctl is applied late enough to win over the cmdline.
        assert machine.succeed("sysctl -n kernel.panic").strip() == "30"
        # R9 asks for pid_max >= 65536 and systemd's 50-pid-max.conf already
        # gives 4194304 — assert the floor, not an exact value, so the claim
        # stays true if systemd changes its default.
        assert int(machine.succeed("sysctl -n kernel.pid_max").strip()) >= 65536

    with subtest("network sysctl hardening"):
        assert machine.succeed("sysctl -n net.ipv4.tcp_syncookies").strip() == "1"
        assert machine.succeed("sysctl -n net.ipv4.conf.all.rp_filter").strip() == "1"
        assert machine.succeed("sysctl -n net.ipv4.conf.all.accept_redirects").strip() == "0"
        assert machine.succeed("sysctl -n net.ipv4.conf.all.accept_source_route").strip() == "0"
        assert machine.succeed("sysctl -n net.ipv4.tcp_rfc1337").strip() == "1"
        assert machine.succeed("sysctl -n net.core.bpf_jit_harden").strip() == "2"
        assert machine.succeed("sysctl -n net.ipv4.conf.all.log_martians").strip() == "1"
        assert machine.succeed("sysctl -n net.ipv4.conf.default.log_martians").strip() == "1"
        # Opt-in, enabled on this node — see strictIpv6RouterAdvertisements above.
        assert machine.succeed("sysctl -n net.ipv6.conf.all.accept_ra").strip() == "0"
        assert machine.succeed("sysctl -n net.ipv6.conf.default.accept_ra").strip() == "0"

    with subtest("kernel module blacklist"):
        # modprobe canonicalises module names (hyphens become underscores), so
        # normalise both sides before comparing.
        modprobe_config = machine.succeed("modprobe --showconfig").replace("-", "_")
        for module in ["firewire-core", "firewire-ohci", "firewire-sbp2",
                       "dccp", "sctp", "rds", "tipc",
                       "cramfs", "freevxfs", "jffs2", "hfs", "hfsplus"]:
            needle = "blacklist " + module.replace("-", "_")
            assert needle in modprobe_config, f"{module} not blacklisted"

    with subtest("scheduler access allowlist"):
        machine.wait_for_unit("cron.service")
        # Covers the /etc/at friction: environment.etc populates /etc/at/at.allow
        # while atd's own preStart runs `install -dm755 -o atd -g atd /etc/at`
        # over the same directory. If those fought, atd would not come up.
        machine.wait_for_unit("atd.service")

        # NixOS paths, not the ones the usual baselines cite: vixie cron reads
        # /var/cron/cron.allow and the atd module sets etcdir=/etc/at.
        assert machine.succeed("cat /var/cron/cron.allow").strip() == "root"
        assert machine.succeed("cat /etc/at/at.allow").strip() == "root"

        # The security property: an unprivileged user is refused by both, even
        # though the upstream preStart left a permissive empty *.deny in place.
        # `crontab -l` also exits non-zero for an *allowed* user with no crontab,
        # so match the refusal message rather than the exit status alone.
        cron_denied = machine.fail("su -l schedtest -c 'crontab -l' 2>&1")
        assert "not allowed" in cron_denied, f"unexpected crontab output: {cron_denied}"
        at_denied = machine.fail("su -l schedtest -c 'echo true | at now + 1 hour' 2>&1")
        assert "permission" in at_denied.lower(), f"unexpected at output: {at_denied}"

        # Root keeps a full round-trip through both — an allowlist that locks out
        # root too would satisfy every assertion above and be useless.
        machine.succeed("echo '* * * * * true' | crontab -")
        assert "* * * * * true" in machine.succeed("crontab -l")
        machine.succeed("crontab -r")
        machine.succeed("echo true | at now + 1 hour")
        assert machine.succeed("atq").strip() != "", "root's at job was not queued"

    with subtest("ssh hardening"):
        machine.wait_for_unit("sshd.service")
        # OpenSSH ≥ 10 dumps CamelCase keywords ("PasswordAuthentication no");
        # earlier versions lowercased them. Normalise before matching, so the
        # assertions survive either casing.
        sshd_config = machine.succeed("sshd -T").lower()
        assert "passwordauthentication no" in sshd_config
        assert "permitrootlogin no" in sshd_config
        assert "loglevel verbose" in sshd_config
        # Assert the relic's tuned values, not merely that the keyword exists:
        # sshd dumps PerSourcePenalties whether or not we set anything.
        assert "crash:3600" in sshd_config
        assert "authfail:3600" in sshd_config
        assert "max:86400" in sshd_config

        # The state manifest's host keys are the ones sshd actually loads, and
        # they exist. Only the manifest's /etc/ssh entries are compared, so a
        # relic added to this node later does not break the subtest; paths come
        # from the raw `sshd -T`, since sshd_config above is lowercased. A JSON
        # list of plain strings is also a Python list literal.
        manifest = [
            p for p in ${builtins.toJSON (map (e: e.path) nodes.machine.stc.relics.state.paths)}
            if p.startswith("/etc/ssh/")
        ]
        loaded = [
            line.split()[1]
            for line in machine.succeed("sshd -T").splitlines()
            if line.lower().startswith("hostkey ")
        ]
        assert loaded and sorted(manifest) == sorted(loaded), f"{manifest} vs {loaded}"
        for path in manifest:
            machine.succeed(f"test -s {path}")

    with subtest("ssh banner"):
        banner_lines = [
            line for line in machine.succeed("sshd -T").splitlines()
            if line.lower().startswith("banner ")
        ]
        assert len(banner_lines) == 1, f"expected one Banner line, got {banner_lines}"
        banner_path = banner_lines[0].split()[1]
        assert banner_path.startswith("/nix/store/"), f"unexpected banner path: {banner_path}"
        assert "Authorized access only" in machine.succeed(f"cat {banner_path}")

    with subtest("authorized keys come from the flake only"):
        rendered = [
            line for line in machine.succeed("sshd -T").splitlines()
            if line.lower().startswith("authorizedkeysfile ")
        ]
        assert len(rendered) == 1, f"expected one AuthorizedKeysFile line, got {rendered}"
        paths = rendered[0].split(None, 1)[1].strip()
        assert paths == "/etc/ssh/authorized_keys.d/%u", f"unexpected search path: {paths}"
        assert "%h" not in paths, f"the home directory is still in the auth path: {paths}"

        # -n is load-bearing: without it ssh reads the console's stdin and eats
        # the marker the test driver writes there, which surfaces as the driver
        # failing to parse an exit status rather than as an SSH problem.
        ssh = (
            "ssh -n -i /etc/proving-ssh-key"
            " -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
            " -o BatchMode=yes -o ConnectTimeout=10"
            " -o PreferredAuthentications=publickey"
        )

        # The rendered path is only half the claim: prove that a declared key
        # still authenticates, or a total lockout would satisfy the assertion
        # above and look like success.
        assert machine.succeed(f"{ssh} declared@127.0.0.1 id -un").strip() == "declared"

        # Same key, planted by hand. Control first - the file sshd would have
        # read is in place, correctly owned, byte-identical to the declared one
        # - so the refusal below cannot be blamed on a broken fixture.
        machine.succeed("install -d -m 700 -o homedir -g users /home/homedir/.ssh")
        machine.succeed(
            "install -m 600 -o homedir -g users"
            " /etc/ssh/authorized_keys.d/declared /home/homedir/.ssh/authorized_keys"
        )
        planted = machine.succeed("cat /home/homedir/.ssh/authorized_keys").strip()
        issued = machine.succeed("cat /etc/ssh/authorized_keys.d/declared").strip()
        assert planted == issued, "the planted key is not the declared one"
        machine.fail(f"{ssh} homedir@127.0.0.1 id -un")
  '';
}
