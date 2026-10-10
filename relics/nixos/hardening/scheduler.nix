# Relic: Scheduler Access
# Restricts the classic job schedulers — cron and at — to an explicit allowlist.
#
# This relic NEVER enables a scheduler. Its whole config is guarded by
# `mkIf config.services.<x>.enable`, so it is inert on a host that schedules with
# systemd timers — which is every STC machine today. It exists for the host that
# does run cron or atd, because nixpkgs deliberately opens both to all local
# users:
#
#   - Vixie cron upstream is closed by default: with neither cron.allow nor
#     cron.deny, only root may own a crontab. The NixOS module undoes that in its
#     preStart — "By default, allow all users to create a crontab. This is
#     denoted by the existence of an empty cron.deny file."
#   - The atd module does the same, touching an empty /etc/at/at.deny.
#
# And cron can switch itself on: `services.cron.enable` defaults to
# `mkDefault (allFiles != [])`, so any third-party module that sets
# `services.cron.systemCronJobs` starts the daemon — open to everyone — without
# the consumer ever asking for it. That is the case this relic catches and that
# documentation could not.
#
# Paths are the ones NixOS actually uses, not the ones the usual baselines cite:
# /var/cron/cron.allow (not /etc/cron.allow) and /etc/at/at.allow (not
# /etc/at.allow — the atd module sets etcdir=/etc/at).
#
# No ANSSI-BP-028 rule covers scheduler access, and STC claims no CIS
# conformance; this relic stands on the auto-enable trap above, not on a
# referential. See docs reference/anssi-bp-028.md.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.stc.relics.hardening.scheduler;

  # Both cron and at read one username per line, and both evaluate the allow
  # file *first*: once it exists, the empty deny file the upstream preStart
  # touches is never consulted. Nothing to delete, so no race with preStart.
  allowFile =
    pkgs.writeText "scheduler-allow"
    (lib.concatMapStrings (user: user + "\n") cfg.allowedUsers);
in {
  options.stc.relics.hardening.scheduler = {
    enable = lib.mkEnableOption "cron/at access restricted to an explicit allowlist";

    allowedUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["root"];
      example = ["root" "backup"];
      description = ''
        Users allowed to schedule jobs with `crontab` and `at`. Written to
        `/var/cron/cron.allow` and `/etc/at/at.allow`, each of which takes
        precedence over the permissive `*.deny` file the upstream NixOS modules
        create.

        Both files are rewritten from the Nix store on every activation, so a
        hand-edited `/var/cron/cron.allow` will not survive a rebuild — that is
        the point of declaring the allowlist here.

        Note that a system crontab declared through `services.cron.systemCronJobs`
        is unaffected: it runs from `/etc/crontab` as root and never goes through
        the per-user `crontab` command this list gates.
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = cfg.allowedUsers != [];
          message = ''
            stc.relics.hardening.scheduler.allowedUsers is empty. An empty allow
            file locks out every user including root, which is a total lockdown
            dressed up as a typo. Disable the relic instead, or list root.
          '';
        }
      ];
    }

    (lib.mkIf config.services.cron.enable {
      # /var, so environment.etc cannot do it. tmpfiles runs before the units, so
      # the file is in place before cron's own preStart looks for it. "L+"
      # replaces whatever is there, which keeps the content declarative.
      # /var/cron is created explicitly rather than relying on tmpfiles creating
      # parent directories.
      systemd.tmpfiles.rules = [
        "d /var/cron 0755 root root -"
        "L+ /var/cron/cron.allow - - - - ${allowFile}"
      ];
    })

    (lib.mkIf config.services.atd.enable {
      # Mode and group mirror the at.deny the atd module creates itself: the `at`
      # binary is a setuid/setgid atd wrapper, so it reads this as uid atd, not
      # as the calling user.
      environment.etc."at/at.allow" = {
        source = allowFile;
        user = "root";
        group = "atd";
        mode = "0640";
      };
    })
  ]);
}
