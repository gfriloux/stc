# Schematic: Dreadnought
# A NixOS EC2 instance deployed from a sarcophagus-aws AMI, managed via deploy-rs.
#
# Pre-flight:
#   1. Launch an EC2 instance from a sarcophagus-aws AMI.
#   2. On the instance, run: nixos-generate-config --show-hardware-config
#      Paste the output into hardware-configuration.nix.
#   3. Set networking.hostId to the value used when building the AMI.
#   4. Add your SSH public key to users.users.admin.openssh.authorizedKeys.keys.
#   5. Set deploy.nodes.dreadnought.hostname to the instance's public IP or DNS.
#   6. just deploy
{
  description = "Dreadnought — NixOS EC2 instance managed via deploy-rs";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    stc = {
      url = "path:../..";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    stc,
    deploy-rs,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    nixosConfigurations.dreadnought = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        # Running-system profile: ZFS + impermanence + hardening + AWS platform.
        # Injects impermanence.nixosModules.impermanence automatically.
        stc.nixosModules.cogitator-dreadnought

        # Add service cogitators here, for example:
        # stc.nixosModules.cogitator-docker-server
        # stc.nixosModules.cogitator-vm
        (
          {...}: {
            stc.cogitator.dreadnought = {
              enable = true;
              # poolName must match the pool name used when building the AMI (default: "vmpool").
              poolName = "vmpool";
              impermanence.extraDirectories = [
                "/var/db/sudo/lectured"
              ];
            };

            # Activate additional cogitators here, for example:
            # stc.cogitator.docker-server.enable = true;
            # stc.cogitator.vm = { enable = true; username = "admin"; authorizedKeys = [ ... ]; };

            networking.hostName = "dreadnought";
            # Must match the hostId used when building the sarcophagus-aws AMI.
            networking.hostId = "cafebabe";

            users = {
              mutableUsers = false;
              # Set to false and add your SSH key below before deploying.
              allowNoPasswordLogin = true;
              users.admin = {
                isNormalUser = true;
                extraGroups = ["wheel"];
                openssh.authorizedKeys.keys = [
                  # "ssh-ed25519 AAAA... you@host"
                ];
              };
            };

            security.sudo.wheelNeedsPassword = false;

            time.timeZone = "UTC";
            i18n.defaultLocale = "en_US.UTF-8";

            system.stateVersion = "24.11";
          }
        )
      ];
    };

    # deploy-rs deployment target.
    # Replace hostname with the instance's public IP or DNS name.
    deploy.nodes.dreadnought = {
      hostname = "REPLACE_WITH_EC2_IP_OR_DNS";
      profiles.system = {
        sshUser = "admin";
        user = "root";
        path = deploy-rs.lib.${system}.activate.nixos self.nixosConfigurations.dreadnought;
      };
    };

    # Integrate deploy-rs schema checks into nix flake check.
    checks.${system} = deploy-rs.lib.${system}.deployChecks self.deploy;

    # Dev shell providing the deploy binary.
    devShells.${system}.default = pkgs.mkShell {
      packages = [deploy-rs.packages.${system}.deploy-rs];
    };
  };
}
