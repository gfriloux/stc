# Schematic: Local VM
# A QEMU/KVM virtual machine with ZFS + impermanence + full hardening.
# Use this as a starting point for local development VMs.
#
# Pre-flight:
#   1. Generate a unique hostId: head -c4 /dev/urandom | od -A none -t x4 | tr -d ' \n'
#      Replace the placeholder networking.hostId below with your value.
#   2. Add your SSH public key to stc.cogitator.vm.authorizedKeys.
#   3. nix build .#nixosConfigurations.local-vm.config.system.build.qcow2
#
# Boot with QEMU:
#   qemu-system-x86_64 -enable-kvm -m 4096 -drive file=result,format=qcow2
{
  description = "Local VM schematic — ZFS + impermanence + hardening";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    stc = {
      url = "path:../..";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    stc,
    ...
  }: {
    nixosConfigurations.local-vm = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        # Disk image builder: ZFS + impermanence + hardening + qcow2.
        # Injects disko and impermanence modules automatically.
        stc.nixosModules.cogitator-sarcophagus-kvm

        # Base user profile: fish, SSH, optional Docker, Nix GC.
        stc.nixosModules.cogitator-vm

        (
          _: {
            stc.cogitator.sarcophagus-kvm = {
              enable = true;
              # poolName = "vmpool";  # default
              impermanence.extraDirectories = ["/var/db/sudo/lectured"];
            };

            stc.cogitator.vm = {
              enable = true;
              username = "admin";
              authorizedKeys = [
                # "ssh-ed25519 AAAA... you@host"
              ];
              docker.enable = false;
            };

            networking.hostName = "local-vm";
            # Generate with: head -c4 /dev/urandom | od -A none -t x4 | tr -d ' \n'
            networking.hostId = "deadc0de";

            users.mutableUsers = false;
            users.users.admin.initialPassword = "changeme";
            users.users.root.initialPassword = "changeme";

            security.sudo.wheelNeedsPassword = false;

            time.timeZone = "UTC";
            i18n.defaultLocale = "fr_FR.UTF-8";
            console.keyMap = "fr";

            system.stateVersion = "24.11";
          }
        )
      ];
    };
  };
}
