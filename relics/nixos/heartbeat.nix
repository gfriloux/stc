# Relic: heartbeat
#
# A dead man's switch for scheduled jobs: each time a named unit SUCCEEDS, it
# pings a URL the consumer owns (an Uptime Kuma push monitor, healthchecks.io,
# …), and the receiver alerts when the pings stop. Every other signal in STC
# detects a service answering badly now; this one detects an event that did
# not happen — a backup that silently stopped running reads as "nothing to
# report" otherwise.
#
# Success only. A ping on "the job ran" would hide exactly the failure this
# exists to catch. systemd's OnSuccess= is not enough on its own: it fires when
# the unit enters the inactive state, and a long-running service stopped
# midway (systemctl stop, a shutdown) ends there with Result=success, because
# systemd counts its SIGTERM as a clean end for a daemon. So the heartbeat
# unit checks the triggering run's outcome before pinging — Result=success and
# a main process that EXITED rather than being killed — and stays silent
# otherwise. Measured in the proving; a oneshot stopped midway ends failed
# instead, and never fires.
#
# The outcome comes from MONITOR_SERVICE_RESULT / MONITOR_EXIT_CODE /
# MONITOR_UNIT, which systemd hands to an OnSuccess= unit as one snapshot when
# it spawns it — not from `systemctl show`, whose values a quick re-run of the
# watched unit (Restart=) would already have reset. A manual start of the
# heartbeat unit has no such variables, and does not ping.
#
# Exit status is not checked: Result=success with an exited process already
# means status 0 or a status the unit declares in SuccessExitStatus=. What the
# gate cannot see is a program that catches SIGTERM and exits 0 on its own:
# for systemd that is a finished run.
#
# The ping runs in its own unit, not in an ExecStopPost of the observed one:
# the observed unit's user and sandbox may forbid the network, and a failed
# ping must never turn a successful job into a failed one. A failed ping fails
# stc-heartbeat-<unit>.service, on its own.
#
# The URL is a secret: whoever knows it can feed the receiver and silence the
# alert. It is read at runtime from urlFile through LoadCredential (the curl
# runs under DynamicUser, not root), and reaches curl on stdin, never on its
# command line.
#
# Transport-agnostic in the same way as docker/notify and smart: STC owns the
# wiring, the consumer owns the receiver, the URL and the alert window.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.stc.relics.heartbeat;

  heartbeatUnit = name: "stc-heartbeat-${name}";

  pingScript = name:
    pkgs.writeShellScript "stc-heartbeat-${name}" ''
      set -eu
      unit=''${MONITOR_UNIT:-}
      result=''${MONITOR_SERVICE_RESULT:-}
      code=''${MONITOR_EXIT_CODE:-}
      # "exited": the main process ended on its own. A run stopped midway is
      # "killed" even when Result reads success.
      if [ "$unit" != ${lib.escapeShellArg "${name}.service"} ] || [ "$result" != success ] || [ "$code" != exited ]; then
        echo "${name}.service did not succeed (unit=$unit result=$result exit-code=$code): no ping"
        exit 0
      fi
      # First line only, CR stripped, then escaped for curl's config syntax,
      # where \ and " are special inside a quoted value.
      url=$(${pkgs.coreutils}/bin/head -n 1 "$CREDENTIALS_DIRECTORY/url" | ${pkgs.coreutils}/bin/tr -d '\r' | ${pkgs.gnused}/bin/sed 's/[\\"]/\\&/g')
      # The URL on stdin, not in argv, where any local user could read it.
      printf 'url = "%s"\n' "$url" \
        | ${pkgs.curl}/bin/curl --config - --fail --silent --show-error \
            --retry ${toString cfg.retries} --retry-all-errors \
            --max-time ${toString cfg.timeoutSec} --output /dev/null
    '';

  isRealService = s: s.script != "" || s.serviceConfig ? ExecStart;
  remainsAfterExit = s: lib.elem (s.serviceConfig.RemainAfterExit or false) [true "yes" "true" "on" "1"];
in {
  options.stc.relics.heartbeat = {
    enable = lib.mkEnableOption "success-only heartbeats from named systemd units";

    units = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options.packageUnit = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            The unit comes from systemd.packages (fstrim, …), so its
            definition is not in systemd.services and the existence check
            cannot see it. Set to true to skip that check for this unit.
          '';
        };
        options.urlFile = lib.mkOption {
          type = lib.types.strMatching "/.*";
          example = "/run/secrets/kuma/push-borg";
          description = ''
            File holding the URL to ping on each success, read at runtime.
            The URL is a secret: whoever knows it can silence the alert.
          '';
        };
      });
      default = {};
      example = lib.literalExpression ''
        {
          "borgbackup-job-remote".urlFile = config.sops.secrets."kuma/push-borg".path;
        }
      '';
      description = ''
        Services to watch, by name as in systemd.services (no ".service").
        Each one pings its URL when it succeeds, and only then.
      '';
    };

    retries = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 3;
      description = "curl retries for a failed ping.";
    };

    timeoutSec = lib.mkOption {
      type = lib.types.ints.positive;
      default = 10;
      description = "Seconds each ping attempt may take.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.concatLists (lib.mapAttrsToList (name: u: let
        s = config.systemd.services.${name};
      in [
        {
          assertion = builtins.match "[A-Za-z0-9:_.@-]+" name != null;
          message = "stc.relics.heartbeat.units.\"${name}\": not a valid unit name.";
        }
        {
          # systemd.services.<name> always exists once onSuccess is written
          # into it below, so test for a real definition, not for the key.
          assertion = u.packageUnit || isRealService s;
          message = ''
            stc.relics.heartbeat.units."${name}": no such service in
            systemd.services (it has no script and no ExecStart). A renamed
            unit would otherwise lose its heartbeat silently, and the receiver
            would only tell you once the alert window has passed. A unit
            shipped by a package (systemd.packages) has none either: set
            packageUnit = true for it.
          '';
        }
        {
          assertion = s.enable;
          message = "stc.relics.heartbeat.units.\"${name}\": the service is disabled (enable = false), so it never runs and never pings.";
        }
        {
          assertion = !(remainsAfterExit s);
          message = ''
            stc.relics.heartbeat.units."${name}": the service sets
            RemainAfterExit, so it stays active after it succeeds and never
            reaches the inactive state that triggers the heartbeat.
          '';
        }
      ])
      cfg.units);

    systemd.services =
      lib.mapAttrs' (name: u:
        lib.nameValuePair (heartbeatUnit name) {
          description = "Heartbeat ping for ${name}.service";
          wants = ["network-online.target"];
          after = ["network-online.target"];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = pingScript name;
            DynamicUser = true;
            LoadCredential = "url:${u.urlFile}";
          };
        })
      cfg.units
      // lib.mapAttrs (name: _: {onSuccess = ["${heartbeatUnit name}.service"];}) cfg.units;
  };
}
