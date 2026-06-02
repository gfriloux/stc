# The Cogitator
# Profiles: curated assemblages of relics for specific purposes.
# Where a relic is a single cog, a profile is the entire mechanism.
#
# Profiles are exposed as homeModules/nixosModules under the
# "cogitator-" prefix (e.g. homeModules.cogitator-enginseer).
# Activate a profile, and the Cogitator does the rest.
{inputs, ...}: {
  flake.nixosModules = {
    # Full hardening suite — composes kernel + network + filesystem + ssh relics.
    cogitator-hardening = ./nixos/hardening.nix;
    # Base VM profile: fish, SSH, user, Docker, Nix GC.
    cogitator-vm = ./nixos/vm.nix;
    # Full Docker reverse-proxy stack: Traefik + CrowdSec + ntfy notifications.
    cogitator-docker-server = ./nixos/docker-server.nix;
    # KDE Plasma 6 Wayland desktop: Plasma 6 + Pipewire.
    cogitator-plasma = ./nixos/plasma.nix;
    # Gaming setup: AMD GPU + Pipewire + Steam.
    cogitator-gaming = ./nixos/gaming.nix;

    # QEMU/KVM disk image: ZFS + impermanence + hardening + qcow2 builder.
    cogitator-sarcophagus-kvm = {...}: {
      imports = [
        inputs.disko.nixosModules.disko
        inputs.impermanence.nixosModules.impermanence
        ./nixos/sarcophagus-kvm.nix
      ];
    };

    # AWS AMI disk image: ZFS + impermanence + hardening + AWS platform + raw builder.
    cogitator-sarcophagus-aws = {...}: {
      imports = [
        inputs.disko.nixosModules.disko
        inputs.impermanence.nixosModules.impermanence
        ./nixos/sarcophagus-aws.nix
      ];
    };

    # EC2 running-system profile: ZFS + impermanence + hardening + AWS platform.
    # For instances deployed from a sarcophagus-aws AMI.
    cogitator-dreadnought = {...}: {
      imports = [
        inputs.impermanence.nixosModules.impermanence
        ./nixos/dreadnought.nix
      ];
    };
  };

  flake.homeModules = {
    # Full CLI toolkit for a field-deployed Techpriest.
    cogitator-enginseer = {...}: {
      imports = [
        inputs.gitflow-toolkit.homeModules.gitflow-toolkit
        inputs.catppuccin.homeModules.catppuccin
        inputs.television-ssh.homeModules.default
        ./home/enginseer
      ];
    };

    # Desktop GUI profile: kitty terminal, zen-browser, GIMP, VLC.
    cogitator-desktop = {...}: {
      imports = [
        inputs.zen-browser.homeModules.beta
        ./home/desktop.nix
      ];
    };
  };
}
