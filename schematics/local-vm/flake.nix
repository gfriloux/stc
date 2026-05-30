# Schematic: Local VM
# A QEMU/KVM virtual machine with ZFS + impermanence + full hardening.
# Use this as a starting point for local development VMs.
#
# Build the qcow2 image:
#   nix build .#nixosConfigurations.local-vm.config.system.build.qcow2
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

    # disko's NixOS module is not injected by any STC module, so the consumer
    # must import it. Reuse STC's exact version to avoid drift.
    disko.follows = "stc/disko";
  };

  outputs =
    {
      nixpkgs,
      stc,
      disko,
      ...
    }:
    {
      nixosConfigurations.local-vm = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          # disko defines the `disko.devices` option used by the layout below.
          # impermanence is NOT imported here — relics-impermanence injects it internally.
          disko.nixosModules.disko

          # STC relics
          stc.nixosModules.relics-boot
          stc.nixosModules.relics-zfs
          stc.nixosModules.relics-networking
          stc.nixosModules.relics-impermanence

          # STC cogitators
          stc.nixosModules.cogitator-hardening
          stc.nixosModules.cogitator-vm

          # Disk layout
          (stc.lib.layouts.zfs-local-vm { poolName = "vmpool"; })

          # qcow2 image builder
          ./qcow2.nix

          # System configuration
          (
            { ... }:
            {
              stc = {
                boot.enable = true;
                zfs.enable = true;
                networking.enable = true;
                hardening.enable = true;
                impermanence = {
                  enable = true;
                  poolName = "vmpool";
                  extraDirectories = [
                    "/var/db/sudo/lectured"
                  ];
                };
                cogitator.vm = {
                  enable = true;
                  username = "admin";
                  authorizedKeys = [
                    # "ssh-ed25519 AAAA... you@host"
                  ];
                  docker.enable = false;
                };
              };

              # QEMU virtio drivers — must be loaded early so /dev/vda exists
              # before ZFS tries to import the pool.
              boot.initrd.kernelModules = [ "virtio_pci" "virtio_blk" ];

              # virtio disks have no by-id entries in QEMU.
              boot.zfs.devNodes = "/dev";

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

              environment.systemPackages = [ ];
              system.stateVersion = "24.11";
            }
          )
        ];
      };
    };
}
