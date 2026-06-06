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
  };

  outputs = {
    nixpkgs,
    stc,
    ...
  }: {
    nixosConfigurations.aws-ami = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        # Disk image builder: ZFS + impermanence + hardening + AWS platform + raw image.
        # Injects disko and impermanence modules automatically.
        stc.nixosModules.cogitator-sarcophagus-aws

        (
          _: {
            stc.cogitator.sarcophagus-aws = {
              enable = true;
              # poolName = "vmpool";    # default
              # rootSize = 4096;        # MiB — default
              impermanence.extraDirectories = ["/var/db/sudo/lectured"];
            };

            networking.hostName = "aws-ami";
            # Replace with a unique value before deploying.
            # Generate with: head -c4 /dev/urandom | od -A none -t x4 | tr -d ' \n'
            networking.hostId = "cafebabe";

            users = {
              mutableUsers = false;
              users.root.initialPassword = "changeme";
              users.admin = {
                isNormalUser = true;
                extraGroups = ["wheel"];
                initialPassword = "changeme";
                openssh.authorizedKeys.keys = [
                  # "ssh-ed25519 AAAA... you@host"
                ];
              };
            };

            # Virtio block driver must be loaded early so /dev/vda is present
            # before ZFS tries to import the pool.
            boot.initrd.kernelModules = [
              "virtio_pci"
              "virtio_blk"
            ];

            security.sudo.wheelNeedsPassword = false;

            time.timeZone = "UTC";
            i18n.defaultLocale = "en_US.UTF-8";

            system.stateVersion = "24.11";
          }
        )
      ];
    };
  };
}
