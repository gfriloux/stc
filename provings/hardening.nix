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
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    with subtest("kernel sysctl hardening"):
        assert machine.succeed("sysctl -n kernel.kptr_restrict").strip() == "2"
        assert machine.succeed("sysctl -n kernel.randomize_va_space").strip() == "2"
        assert machine.succeed("sysctl -n kernel.unprivileged_bpf_disabled").strip() == "1"
        assert machine.succeed("sysctl -n kernel.yama.ptrace_scope").strip() == "1"
        assert machine.succeed("sysctl -n fs.suid_dumpable").strip() == "0"

    with subtest("network sysctl hardening"):
        assert machine.succeed("sysctl -n net.ipv4.tcp_syncookies").strip() == "1"
        assert machine.succeed("sysctl -n net.ipv4.conf.all.rp_filter").strip() == "1"
        assert machine.succeed("sysctl -n net.ipv4.conf.all.accept_redirects").strip() == "0"

    with subtest("ssh hardening"):
        machine.wait_for_unit("sshd.service")
        sshd_config = machine.succeed("sshd -T")
        assert "passwordauthentication no" in sshd_config
        assert "permitrootlogin no" in sshd_config
  '';
}
