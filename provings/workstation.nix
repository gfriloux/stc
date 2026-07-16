# Proving: workstation cogitator
# Boots a VM with stc.cogitator.workstation enabled and asserts the profile wires
# its three concerns together: the hardening socle (kernel/network/module
# blacklist), YubiKey support, and the selected desktop environment.
#
# Scope note — this proving asserts *wiring*, not the graphical session. Plasma is
# heavy to bring up in a VM; we only wait for multi-user.target and check that the
# display-manager unit exists, without requiring a running graphical login.
# Filesystem mount hardening is not asserted (the qemu-vm module replaces
# `fileSystems`; see the hardening proving for the rationale).
{self}: {
  name = "workstation";

  nodes.machine = {
    imports = [self.nixosModules.cogitator-workstation];
    stc.cogitator.workstation.enable = true;
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    with subtest("hardening socle active"):
        assert machine.succeed("sysctl -n kernel.kptr_restrict").strip() == "2"
        assert machine.succeed("sysctl -n net.core.bpf_jit_harden").strip() == "2"
        # module blacklist wired (modprobe canonicalises hyphens to underscores)
        modprobe_config = machine.succeed("modprobe --showconfig").replace("-", "_")
        assert "blacklist firewire_core" in modprobe_config
        assert "blacklist dccp" in modprobe_config

    with subtest("yubikey system support"):
        machine.succeed("systemctl cat pcscd.service")

    with subtest("desktop environment wired"):
        machine.succeed("systemctl cat display-manager.service")
  '';
}
