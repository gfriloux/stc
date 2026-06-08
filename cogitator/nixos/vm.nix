# Cogitator: VM Base Profile
#
# Opinionated base for a NixOS development or staging VM:
# fish shell, SSH, a primary user with wheel access, optional Docker,
# and automatic Nix GC to keep store bloat under control.
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

    nix = {
      gc = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable automatic Nix garbage collection.";
        };
        dates = lib.mkOption {
          type = lib.types.str;
          default = "weekly";
          description = "When to run Nix GC (systemd calendar expression).";
        };
        keepDays = lib.mkOption {
          type = lib.types.int;
          default = 5;
          description = "Delete Nix store paths older than this many days.";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    nix.optimise.automatic = true;

    nix.gc = lib.mkIf cfg.nix.gc.enable {
      automatic = true;
      dates = cfg.nix.gc.dates;
      options = "--delete-older-than ${toString cfg.nix.gc.keepDays}d";
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
