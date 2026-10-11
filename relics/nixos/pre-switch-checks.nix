# Relic: Pre-Switch Checks
# Runs checks on the target machine after the closure has been copied but before
# it is activated. A check that exits non-zero aborts the switch with the old
# system still running.
#
# Two failure modes a consumer cannot guard against on their own:
#
#   1. Deploying the wrong host's closure. A multi-host consumer deploys with
#      near-identical commands:
#
#        nixos-rebuild switch --flake .#hostA --target-host user@hostA
#        nixos-rebuild switch --flake .#hostB --target-host user@hostB
#
#      Swap the flake attribute or the target and host A's closure activates on
#      host B: wrong containers, wrong users, wrong secrets — and if the change
#      touches sshd or sudo, possibly no way back in.
#   2. No diff on a remote deploy. Locally you see what changed; with
#      --target-host, nixos-rebuild prints nothing, so an operator activates a
#      closure on a production host without seeing which packages moved.
#
# THE ONLY ESCAPE HATCH IS NIXOS_NO_CHECK=1, and that is a measured fact rather
# than a preference. srvos offers an EXPECTED_HOSTNAME variable; it cannot work
# through nixos-rebuild. nixos-rebuild-ng runs switch-to-configuration under
# `/usr/bin/env -i` with a closed allowlist of three variables — LOCALE_ARCHIVE,
# NIXOS_NO_CHECK, NIXOS_INSTALL_BOOTLOADER — wrapped in `systemd-run -E` for the
# same three, and only NIXOS_NO_CHECK is in sudo's env_keep. A variable of ours
# would reach nothing. Cost of using the upstream hatch, stated in the docs: it
# disables *all* pre-switch checks, including upstream's own switch inhibitors.
#
# AND THERE IS NO PROMPT. srvos asks for confirmation on stdin. Under
# `nixos-rebuild --target-host` the script runs through ssh beneath
# `systemd-run --pipe`, where stdin is not a reliable terminal; and under the
# `set -euo pipefail` that writeShellApplication imposes, a `read` from an empty
# stdin returns non-zero and aborts the switch anyway. Prompting is therefore a
# non-deterministic way of spelling "abort". We keep the determinism.
#
# Shape note: every fragment is concatenated into a single
# pkgs.writeShellApplication, which runs shellcheck at build time — so an
# unquoted expansion or an unused variable breaks the *system build*, for every
# consumer, not just a deploy. That wrapper also runs each fragment inside
# `( set -e … ) >&2`, so stdout is already stderr: no `>&2` belongs below.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.stc.relics.preSwitchChecks;
in {
  options.stc.relics.preSwitchChecks = {
    enable = lib.mkEnableOption ''
      checks that run on the target machine before a new closure is activated
    '';

    hostnameGuard = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Abort the switch when the closure being activated does not belong to the
        machine running it.

        The expected name is baked in at evaluation time from
        `networking.hostName`. That is not circular: the check travels *inside*
        the incoming closure, so by construction that value is the name of the
        host this closure was built for.

        Comparison is on the short name — the part before the first dot on both
        sides — because systemd may have set the FQDN when `networking.domain` is
        defined, and a strict comparison would abort a correct deploy.

        Skipped in three situations, each deliberate:

        - action `dry-activate`, which activates nothing;
        - `/run/booted-system` absent, which means an install is in progress
          (`nixos-enter` bind-mounts only `/dev`, `/sys` and `/proc`, so `/run`
          inside the chroot belongs to the target and is empty, while
          `/proc/sys/kernel/hostname` is still the installer's). Without this,
          the guard would abort every nixos-anywhere install, which is how STC's
          schematics are installed;
        - `networking.hostName` empty, a legitimate configuration for a host
          named by DHCP, where there is no expected name to compare against.

        Note that it *does* run for action `boot`, unlike upstream's switch
        inhibitors: writing the wrong host's bootloader entry is precisely the
        disaster this guards against, and it would only surface at the next
        reboot.
      '';
    };

    closureDiff = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Print a package diff between `/run/current-system` and the incoming
        closure before activating, using `dix`.

        Purely informational, and it can never fail a switch: a diff tool that
        errors prints a warning and the fragment still exits 0.

        It adds `dix` (~4 MiB unpacked, in the binary cache) to the closure of
        every host that enables it — which is why this is a separate toggle: turn
        it off and keep the hostname guard.

        To use `nvd` instead, set this to `false` and write your own fragment —
        the two have different command lines, so a package option here would be
        a trap:

        ```nix
        system.preSwitchChecks.myDiff = '''
          ''${lib.getExe pkgs.nvd} diff /run/current-system "$1"
        ''';
        ```
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Fragment names are not cosmetic: upstream renders them with
    # `lib.mapAttrsToList`, so they run in attribute-name order — alphabetical.
    # "stcAbortWrongHost" must keep sorting before "stcClosureDiff", otherwise a
    # wrong-host deploy prints a diff of two unrelated closures first and scrolls
    # the abort message out of view. Rename with that in mind.
    system.preSwitchChecks = {
      stcAbortWrongHost = lib.mkIf cfg.hostnameGuard ''
        case "''${2-}" in
          dry-activate) exit 0 ;;
        esac

        # An install is in progress — see the option description. This test is
        # load-bearing, not defensive: without it every fresh install aborts.
        [ -e /run/booted-system ] || exit 0

        expected=${lib.escapeShellArg config.networking.hostName}
        [ -n "$expected" ] || exit 0

        read -r running < /proc/sys/kernel/hostname

        # Short name on both sides: systemd may have set the FQDN.
        if [ "''${running%%.*}" != "''${expected%%.*}" ]; then
          echo "stc: refusing to activate the closure of '$expected' on '$running'."
          echo "stc: deploy the right flake attribute, or re-run with NIXOS_NO_CHECK=1."
          exit 1
        fi
      '';

      stcClosureDiff = lib.mkIf cfg.closureDiff ''
        case "''${2-}" in
          dry-activate) exit 0 ;;
        esac

        [ -e /run/current-system ] || exit 0

        echo "stc: closure diff (current -> incoming):"

        # The `||` is what keeps a cosmetic check from aborting a deploy. Under
        # `set -e` a bare failing command would kill the fragment.
        ${lib.getExe pkgs.dix} /run/current-system "''${1-}" \
          || echo "stc: closure diff unavailable (dix exited non-zero) - continuing."
      '';
    };
  };
}
