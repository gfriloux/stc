# Schematic: Dreadnought
# A NixOS EC2 instance deployed from a sarcophagus-aws AMI, managed via deploy-rs.
#
# ⚠ DO NOT DEPLOY THIS AS-IS. It is a starting point, not a hardened config.
#   Before deploying you MUST:
#     - add your own SSH key (admin has none, so the box is unreachable until you do)
#     - then set allowNoPasswordLogin = false
#     - replace the placeholder hostId "cafebabe" with your AMI's hostId
#   This profile ships passwordless sudo for wheel (wheelNeedsPassword = false)
#   and key-only SSH: anyone who adds a key without re-reading this gets a
#   NOPASSWD root path. Decide that on purpose, not by accident.
#
# Pre-flight:
#   1. Launch an EC2 instance from a sarcophagus-aws AMI.
#   2. On the instance, run: nixos-generate-config --show-hardware-config
#      Paste the output into hardware-configuration.nix.
#   3. Set networking.hostId to the value used when building the AMI.
#   4. Add your SSH public key to users.users.admin.openssh.authorizedKeys.keys,
#      then set users.allowNoPasswordLogin = false.
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
          _: {
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
            # Placeholder — replace with your own. Must match the hostId used
            # when building the sarcophagus-aws AMI.
            networking.hostId = "cafebabe";

            users = {
              mutableUsers = false;
              # ⚠ true only so this example evaluates before you add a key.
              # Add your SSH key below, then set this to false before deploying.
              allowNoPasswordLogin = true;
              users.admin = {
                isNormalUser = true;
                extraGroups = ["wheel"];
                openssh.authorizedKeys.keys = [
                  # "ssh-ed25519 AAAA... you@host"
                ];
              };
            };

            # ⚠ Passwordless sudo for wheel. Combined with key-only SSH this is a
            # direct root path for anyone holding admin's key. Intentional for a
            # deploy-rs target; review it for your threat model.
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
