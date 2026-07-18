# Enginseer — Field-Deployed Techpriest CLI Profile
#
# The Enginseer is the Adeptus Mechanicus operative sent into the field
# to maintain, operate, and commune with machines of all kinds.
# Armed with the finest instruments known to the Omnissiah, they leave
# no system un-diagnosed, no pipeline un-optimized.
#
# This profile assembles the full CLI toolkit of a seasoned Enginseer:
# shell enhancements, dev tooling, git rites, and aesthetic augmentations.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.stc.cogitator.enginseer;
in {
  options.stc.cogitator.enginseer = {
    enable = lib.mkEnableOption "Enginseer CLI profile — full field-deployment toolkit";
  };

  config = lib.mkIf cfg.enable {
    programs = {
      atuin.enable = true;
      bat.enable = true;
      btop.enable = true;

      fish = {
        enable = true;
        shellInit = ''
          oh-my-posh init fish --config ${config.xdg.configHome}/oh-my-posh/dracula.omp.json | source
        '';
        shellAliases = {
          cat = "bat";
          ping = "prettyping";
          cp = "xcp";
        };
      };

      delta = {
        enable = true;
        enableGitIntegration = true;
      };

      direnv = {
        enable = true;
        nix-direnv.enable = true;
        silent = true;
      };

      fzf.enable = true;
      git.enable = true;
      gitflow-toolkit.enable = true;

      gh = {
        enable = true;
        settings = {
          git_protocol = "ssh";
          prompt = "enabled";
        };
      };

      gpg.enable = true;
      helix.enable = true;
      jq.enable = true;
      lsd.enable = true;

      micro = {
        enable = true;
        settings = {
          tabsize = 2;
          tabstospaces = true;
          autoindent = true;
          ruler = true;
          savecursor = true;
          mouse = true;
          "lsp.server" = "nix:nixd";
        };
      };

      nix-search-tv = {
        enable = true;
        enableTelevisionIntegration = true;
      };

      rbw.enable = true;
      television.enable = true;
      television-ssh.enable = true;
      zellij.enable = true;
      zoxide.enable = true;
    };

    home.packages = with pkgs; [
      age
      alejandra
      aria2
      croc
      dive
      doggo
      fastfetch
      fd
      fzf-make
      git-workspace
      glow
      gum
      htop
      just
      ncdu
      nh
      nix-output-monitor
      nix-tree
      nixd
      nvd
      oh-my-posh
      ouch
      p7zip
      prettyping
      pv
      pwgen
      rsync
      sops
      unzip
      viu
      xcp
    ];

    xdg.configFile."oh-my-posh/dracula.omp.json".source =
      ./oh-my-posh/dracula.omp.json;

    catppuccin = {
      flavor = "frappe";
      enable = true;
      # Match the current implicit default explicitly: silences catppuccin/nix's
      # deprecation warning ahead of autoEnable becoming the enrolment toggle.
      autoEnable = true;
    };
  };
}
