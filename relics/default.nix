# The Reliquary
# Sacred NixOS and Home Manager modules, recovered from the Age of Strife.
# Each relic is an atomic, reusable building block.
# Handle with reverence. Import with intention.
#
# NAMESPACE MIGRATION (v2.0)
# Relics expose options under both namespaces for backward compatibility:
#   Legacy (deprecated): stc.boot, stc.zfs, stc.hardening.kernel, stc.docker.traefik, ...
#   Canonical (new):     stc.relics.boot, stc.relics.zfs, stc.relics.hardening.kernel, ...
#
# Using the legacy namespace emits a NixOS deprecation warning at eval time.
# The legacy namespace will be removed in STC v3.0 (January 2027).
{inputs, ...}: {
  flake.nixosModules = {
    # --- System ---
    relics-boot = ./nixos/boot.nix;
    relics-zfs = ./nixos/zfs.nix;
    relics-networking = ./nixos/networking.nix;
    relics-aws = ./nixos/aws.nix;

    # Impermanence needs the upstream module injected via inputs closure.
    relics-impermanence = {...}: {
      imports = [
        inputs.impermanence.nixosModules.impermanence
        ./nixos/impermanence.nix
      ];
    };

    # --- Hardening (individual relics for surgical use) ---
    relics-hardening-kernel = ./nixos/hardening/kernel.nix;
    relics-hardening-network = ./nixos/hardening/network.nix;
    relics-hardening-filesystem = ./nixos/hardening/filesystem.nix;
    relics-hardening-ssh = ./nixos/hardening/ssh.nix;
    relics-hardening-modules = ./nixos/hardening/modules.nix;

    # --- Hardware ---
    relics-amd-gpu = ./nixos/amd-gpu.nix;

    # --- Desktop ---
    relics-pipewire = ./nixos/pipewire.nix;
    relics-plasma6 = ./nixos/plasma6.nix;

    # --- Security tokens ---
    relics-yubikey-system = ./nixos/yubikey.nix;

    # --- Services (native NixOS, no Docker) ---
    relics-traefik = ./nixos/traefik.nix;
    relics-vaultwarden = ./nixos/vaultwarden.nix;

    # --- Docker stack (individual relics for surgical use) ---
    relics-docker-traefik = ./nixos/docker/traefik.nix;
    relics-docker-socket-proxy = ./nixos/docker/socket-proxy.nix;
    relics-docker-crowdsec = ./nixos/docker/crowdsec.nix;
    relics-docker-notify = ./nixos/docker/notify.nix;
  };

  flake.homeModules = {
    relics-kitty = ./home/kitty.nix;
    relics-ghostty = ./home/ghostty.nix;
    relics-yubikey-user = ./home/yubikey.nix;

    # plasma-manager requires its upstream module injected via inputs closure.
    relics-plasma-manager = {...}: {
      imports = [
        inputs.plasma-manager.homeModules.plasma-manager
        ./home/plasma-manager.nix
      ];
    };

    # zen-browser requires its upstream module injected via inputs closure.
    relics-zen-browser = {...}: {
      imports = [
        inputs.zen-browser.homeModules.beta
        ./home/zen-browser.nix
      ];
    };
  };
}
