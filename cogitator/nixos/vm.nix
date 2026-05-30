# Cogitator: VM Base Profile
#
# Opinionated base for a NixOS development or staging VM:
# fish shell, SSH, a primary user with wheel access, optional Docker,
# and automatic Nix GC to keep store bloat under control.
#
# Compose with stc.cogitator.hardening and stc.cogitator.enginseer as needed.
{ config, lib, pkgs, ... }:
let
  cfg = config.stc.cogitator.vm;
in
{
  options.stc.cogitator.vm = {
    enable = lib.mkEnableOption "STC base VM profile";

    username = lib.mkOption {
      type = lib.types.str;
      default = "admin";
      description = "Primary user account created on the VM.";
    };

    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "SSH authorized keys for the primary user.";
    };

    docker = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Docker and add the primary user to the docker group.";
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
      extraGroups = [ "wheel" ] ++ lib.optional cfg.docker.enable "docker";
      shell = pkgs.fish;
      linger = true;
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
