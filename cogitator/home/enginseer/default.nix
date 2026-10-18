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
  options,
  lib,
  pkgs,
  ...
}: let
  cfg = config.stc.cogitator.enginseer;

  # Atuin and fzf both bind Ctrl-R. Atuin's shell integration is sourced after
  # fzf's, so Atuin already wins in practice; clearing fzf's history widget makes
  # that explicit and silences Home Manager's conflict warning. Ctrl-T and Alt-C
  # stay with fzf. The option only exists in Home Manager releases newer than the
  # one STC pins, so it is applied conditionally — older consumers keep the
  # (identical) sourcing-order behaviour without an eval error.
  # mkDefault: the documentation already teaches the way back ("restore the
  # widget ... programs.fzf.historyWidget.command = lib.mkForce null"), which is
  # the admission that a consumer legitimately wants it. Measured — at normal
  # priority a plain `= null` conflicted and mkForce was the only route. The
  # doc loses the mkForce in the same change.
  fzfHistoryWidget =
    lib.optionalAttrs (options.programs.fzf ? historyWidget)
    {historyWidget.command = lib.mkDefault "";};
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
        # mkDefault: silencing direnv's "loading" chatter is a taste, and
        # someone debugging why an environment did not load wants it back.
        silent = lib.mkDefault true;
      };

      fzf =
        {
          enable = true;
        }
        // fzfHistoryWidget;

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
        # Every setting is mkDefault, because the documentation already promised
        # it: the Enginseer page says of exactly these values "Override any of
        # them from your own home configuration". Measured before this change —
        # `programs.micro.settings.mouse = false` raised "has conflicting
        # definition values" and only `lib.mkForce false` got through, so the
        # promise was false. These are an editor's taste and nothing in the
        # profile depends on them.
        settings = {
          tabsize = lib.mkDefault 2;
          tabstospaces = lib.mkDefault true;
          autoindent = lib.mkDefault true;
          ruler = lib.mkDefault true;
          savecursor = lib.mkDefault true;
          mouse = lib.mkDefault true;
          "lsp.server" = lib.mkDefault "nix:nixd";
        };
      };

      nix-search-tv = {
        enable = true;
        enableTelevisionIntegration = true;
      };

      rbw.enable = true;

      # Connection multiplexing only — the universal part. Host-specific
      # blocks (identityFiles, secrets) stay in the consumer's config.
      # enableDefaultConfig = false drops Home Manager's legacy default block
      # (falling back to OpenSSH's own safe defaults) and silences its
      # deprecation warning, matching the consumer's setup.
      ssh = {
        enable = true;
        enableDefaultConfig = lib.mkDefault false;
        settings."*" = {
          ControlMaster = "auto";
          ControlPath = "~/.ssh/sockets/%r@%h:%p";
          ControlPersist = "60m";
          SetEnv.TERM = "xterm-256color";
        };
      };

      television.enable = true;
      television-ssh.enable = true;
      zellij.enable = true;
      zoxide.enable = true;
    };

    services.gpg-agent = {
      enable = true;
      # SSH auth is delegated to a dedicated ssh-agent by the consumer, not gpg.
      #
      # mkDefault: that delegation is an assumption about the consumer, not a
      # property of this profile. Using gpg-agent *as* the SSH agent is the
      # standard setup for a smartcard-held authentication key, and at normal
      # priority that consumer had to mkForce the profile to get it. Note the
      # neighbour below was already mkDefault for the same kind of reason.
      enableSshSupport = lib.mkDefault false;
      enableFishIntegration = true;
      # Headless-safe default so the Enginseer works on servers/TTY. GUI profiles
      # (cogitator-desktop) override this with a graphical pinentry.
      pinentry.package = lib.mkDefault pkgs.pinentry-curses;
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

    # ControlPath directory for SSH connection multiplexing (see programs.ssh).
    home.file.".ssh/sockets/.keep".text = "";

    xdg.configFile."oh-my-posh/dracula.omp.json".source =
      ./oh-my-posh/dracula.omp.json;

    catppuccin = {
      flavor = "frappe";
      enable = true;
      # Match the current implicit default explicitly: silences catppuccin/nix's
      # deprecation warning ahead of autoEnable becoming the enrolment toggle.
      #
      # mkDefault, precisely because the line's purpose is to reproduce a
      # default rather than impose a choice. A value whose job is to change
      # nothing has no business being unoverridable — a consumer who wants to
      # theme their tools one by one sets it false and keeps the warning
      # silenced.
      autoEnable = lib.mkDefault true;
    };
  };
}
