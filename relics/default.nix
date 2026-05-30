# The Reliquary
# Sacred NixOS and Home Manager modules, recovered from the Age of Strife.
# Each relic is an atomic, reusable building block.
# Handle with reverence. Import with intention.
{ inputs, ... }: {
  flake.nixosModules = {
    # --- System ---
    relics-boot = ./nixos/boot.nix;
    relics-zfs = ./nixos/zfs.nix;
    relics-networking = ./nixos/networking.nix;
    relics-aws = ./nixos/aws.nix;

    # Impermanence needs the upstream module injected via inputs closure.
    relics-impermanence =
      { ... }:
      {
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

    # --- Services (native NixOS, no Docker) ---
    relics-traefik = ./nixos/traefik.nix;
    relics-vaultwarden = ./nixos/vaultwarden.nix;

    # --- Docker stack (individual relics for surgical use) ---
    relics-docker-traefik = ./nixos/docker/traefik.nix;
    relics-docker-crowdsec = ./nixos/docker/crowdsec.nix;
    relics-docker-notify = ./nixos/docker/notify.nix;
  };

  flake.homeModules = {
    relics-kitty = ./home/kitty.nix;

    # zen-browser requires its upstream module injected via inputs closure.
    relics-zen-browser =
      { ... }:
      {
        imports = [
          inputs.zen-browser.homeModules.beta
          ./home/zen-browser.nix
        ];
      };
  };
}
