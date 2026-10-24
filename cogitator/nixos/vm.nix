# Cogitator: VM Base Profile
#
# Opinionated base for a NixOS development or staging VM:
# fish shell, SSH, a primary user with wheel access, optional Docker,
# and a bounded Nix store (stc.relics.nixHousekeeping, with a 5-day GC window).
#
# Compose with stc.cogitator.hardening and stc.cogitator.enginseer as needed.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.stc.cogitator.vm;
in {
  imports = [
    ../../relics/nixos/nix-housekeeping.nix

    # The GC options moved to the relic in v0.19.0 (#59). A value set on the old
    # path is forwarded at its own priority, so it still beats the 5-day default
    # below.
    (lib.mkRenamedOptionModule ["stc" "cogitator" "vm" "nix" "gc" "enable"] ["stc" "relics" "nixHousekeeping" "gc" "enable"])
    (lib.mkRenamedOptionModule ["stc" "cogitator" "vm" "nix" "gc" "dates"] ["stc" "relics" "nixHousekeeping" "gc" "dates"])
    (lib.mkRenamedOptionModule ["stc" "cogitator" "vm" "nix" "gc" "keepDays"] ["stc" "relics" "nixHousekeeping" "gc" "keepDays"])
  ];

  options.stc.cogitator.vm = {
    enable = lib.mkEnableOption "STC base VM profile";

    username = lib.mkOption {
      type = lib.types.str;
      default = "admin";
      description = "Primary user account created on the VM.";
    };

    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "SSH authorized keys for the primary user.";
    };

    linger = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable systemd lingering for the primary user. Lingering keeps the user's
        systemd instance (and any enabled user services) running without an open
        login session — useful for self-hosted user-level daemons on a headless VM.

        Default true preserves historical behaviour. Set to false on a hardened
        host where user services should only run while the user is logged in.
      '';
    };

    docker = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Enable Docker and add the primary user to the `docker` group.

          Off by default: membership of the `docker` group is equivalent to root
          (the daemon runs as root and the socket grants full control), so it is
          opt-in rather than a silent default. Enable it only when the VM is meant
          to run containers.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    # Store and journal housekeeping is the relic's concern. A development VM is
    # throwaway: keep the 5-day GC window this profile has always had, as a
    # default so the old stc.cogitator.vm.nix.gc.keepDays (renamed above) and
    # the relic's own option both still win.
    stc.relics.nixHousekeeping = {
      enable = lib.mkDefault true;
      gc.keepDays = lib.mkDefault 5;
    };

    programs.fish.enable = true;

    users.users.${cfg.username} = {
      isNormalUser = true;
      extraGroups = ["wheel"] ++ lib.optional cfg.docker.enable "docker";
      shell = pkgs.fish;
      inherit (cfg) linger;
      openssh.authorizedKeys.keys = cfg.authorizedKeys;
    };

    services.openssh.enable = true;

    virtualisation.docker = lib.mkIf cfg.docker.enable {
      enable = true;
    };

    environment.systemPackages = lib.optionals cfg.docker.enable (with pkgs; [
      docker-compose
    ]);
  };
}
