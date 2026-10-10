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
# (kernel, network) is unaffected and IS asserted below.
{self}: {
  name = "hardening";

  nodes.machine = {
    imports = [self.nixosModules.cogitator-hardening];
    stc.cogitator.hardening.enable = true;

    # The banner is opt-in and defaults to null, so the test node has to set it
    # for the subtest below to have anything to assert.
    stc.relics.hardening.ssh.banner = "Authorized access only. All activity is logged.\n";

    # Same reason: RA rejection is opt-in, so the node turns it on to make the
    # sysctl assertion below meaningful. Safe here — the test VM's networking is
    # statically configured by the test driver, it never relies on SLAAC.
    stc.relics.hardening.network.strictIpv6RouterAdvertisements = true;
  };

  testScript = ''
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

    with subtest("ssh banner"):
        banner_lines = [
            line for line in machine.succeed("sshd -T").splitlines()
            if line.lower().startswith("banner ")
        ]
        assert len(banner_lines) == 1, f"expected one Banner line, got {banner_lines}"
        banner_path = banner_lines[0].split()[1]
        assert banner_path.startswith("/nix/store/"), f"unexpected banner path: {banner_path}"
        assert "Authorized access only" in machine.succeed(f"cat {banner_path}")
  '';
}
