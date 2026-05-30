# Schematic: AWS AMI
# A NixOS AMI image for AWS EC2, with ZFS + impermanence + full hardening.
#
# Pre-flight:
#   1. Generate a unique hostId: head -c4 /dev/urandom | od -A none -t x4 | tr -d ' \n'
#      Replace the placeholder networking.hostId below with your value.
#   2. Add your SSH public key to users.users.admin.openssh.authorizedKeys.keys.
#   3. nix build .#nixosConfigurations.aws-ami.config.system.build.awsImage
#   4. Upload to AWS with the tool of your choice. The Omnissiah prefers the CLI.
{
  description = "AWS AMI schematic — ZFS + impermanence + hardening";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    stc = {
      url = "path:../..";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Reuse the exact versions STC depends on to avoid version drift.
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
      nixosConfigurations.aws-ami = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko

          stc.nixosModules.relics-boot
          stc.nixosModules.relics-zfs
          stc.nixosModules.relics-networking
          stc.nixosModules.relics-impermanence
          stc.nixosModules.relics-aws
          stc.nixosModules.cogitator-hardening

          (stc.lib.layouts.zfs-local-vm { poolName = "vmpool"; })

          ./image.nix

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
                  extraDirectories = [ "/var/db/sudo/lectured" ];
                };
                aws = {
                  enable = true;
                  poolName = "vmpool";
                };
              };

              # virtio drivers for QEMU local testing (harmless on real AWS hardware).
              boot.initrd.kernelModules = [ "virtio_pci" "virtio_blk" ];

              networking.hostName = "aws-ami";
              # Replace with a unique value before deploying.
              # Generate with: head -c4 /dev/urandom | od -A none -t x4 | tr -d ' \n'
              networking.hostId = "cafebabe";

              users = {
                mutableUsers = false;
                users.root.initialPassword = "changeme";
                users.admin = {
                  isNormalUser = true;
                  extraGroups = [ "wheel" ];
                  initialPassword = "changeme";
                  openssh.authorizedKeys.keys = [
                    # "ssh-ed25519 AAAA... you@host"
                  ];
                };
              };

              security.sudo.wheelNeedsPassword = false;

              time.timeZone = "UTC";
              i18n.defaultLocale = "en_US.UTF-8";

              environment.systemPackages = [ ];
              system.stateVersion = "24.11";
            }
          )
        ];
      };
    };
}
