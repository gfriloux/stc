# Relic: docker-notify
#
# Runs a consumer-supplied notification command when a watched Docker container
# fails, and restarts unhealthy containers automatically.
#
# Transport-agnostic: STC owns the reusable wiring (health-watch, OnFailure,
# restart policy, opt-in label) but NOT the notification transport. The consumer
# provides `notifyCommand`, which receives everything through the environment:
#   STC_NOTIFY_SERVICE   — the systemd service that entered the failed state
#   STC_NOTIFY_HOSTNAME  — the host, for message titles
# The command reads its own secrets (ntfy topic, webhook token, …); STC stays
# agnostic to the backend, exactly like the *File secrets pattern.
#
# Containers opt in by setting the label defined in stc.relics.docker.notify.watchLabel.
# The relic then wires systemd OnFailure + a health-watch timer for each one.
#
# Recovery vs. give-up: a container that stays `unhealthy` is `docker kill`ed by
# the health-watch every 30s and restarted (Restart=on-failure). With
# StartLimitBurst=3 / StartLimitIntervalSec=300s, three kills inside ~90s trip
# the limit and systemd stops restarting it — the container then stays DOWN.
# This is deliberate (better than crash-looping forever), but the only signal is
# the notification: a persistently-broken service, including the CrowdSec
# IDS/IPS, can end up permanently stopped with nothing else flagging it.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.stc.relics.docker.notify;

  notifyScript = pkgs.writeShellScript "stc-notify-failure" ''
    export STC_NOTIFY_SERVICE="$1"
    export STC_NOTIFY_HOSTNAME=${lib.escapeShellArg cfg.hostname}

    ${cfg.notifyCommand}
  '';

  healthWatchScript = pkgs.writeShellScript "stc-docker-health-watch" ''
    CONTAINER="$1"
    STATUS=$(${pkgs.docker}/bin/docker inspect --format='{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null)
    if [ "$STATUS" = "unhealthy" ]; then
      ${pkgs.docker}/bin/docker kill "$CONTAINER"
    fi
  '';

  watched =
    lib.filterAttrs (
      # Opt-in is the label set to "true", not merely present: a container
      # carrying "<watchLabel>" = "false" must stay unwatched.
      _: c: (c.labels.${cfg.watchLabel} or "false") == "true"
    )
    config.virtualisation.oci-containers.containers;

  # Each watched container maps to two distinct identifiers that must not be
  # conflated:
  #   - unit:      the systemd unit oci-containers actually generates —
  #                serviceName when set, otherwise docker-<name>. Used to attach
  #                OnFailure / Restart / partOf to the *real* unit.
  #   - container: the docker container name (the attribute name). Used by
  #                `docker inspect` / `docker kill` in the health-watch instance.
  # Conflating them (using the attribute name as the unit) silently misfires for
  # any third-party container that does not set serviceName.
  watchedList =
    lib.mapAttrsToList (name: c: {
      container = name;
      unit = c.serviceName or "docker-${name}";
    })
    watched;
in {
  imports = [
    (lib.mkRenamedOptionModule ["stc" "docker" "notify" "enable"] ["stc" "relics" "docker" "notify" "enable"])
    (lib.mkRenamedOptionModule ["stc" "docker" "notify" "hostname"] ["stc" "relics" "docker" "notify" "hostname"])
    (lib.mkRenamedOptionModule ["stc" "docker" "notify" "watchLabel"] ["stc" "relics" "docker" "notify" "watchLabel"])
    # ntfy is no longer STC's concern — the transport moved to `notifyCommand`.
    # These options are removed (not renamed): point notifyCommand at your own
    # curl/webhook invocation, reading STC_NOTIFY_SERVICE / STC_NOTIFY_HOSTNAME.
    (lib.mkRemovedOptionModule ["stc" "docker" "notify" "ntfy" "baseUrl"] ''
      stc.relics.docker.notify no longer speaks ntfy. Move your ntfy call into
      stc.relics.docker.notify.notifyCommand, which receives STC_NOTIFY_SERVICE
      and STC_NOTIFY_HOSTNAME in the environment.
    '')
    (lib.mkRemovedOptionModule ["stc" "docker" "notify" "ntfy" "topicFile"] ''
      stc.relics.docker.notify no longer speaks ntfy. Read the topic file inside
      stc.relics.docker.notify.notifyCommand instead (STC stays agnostic to the
      notification backend, like the *File secrets pattern).
    '')
    (lib.mkRemovedOptionModule ["stc" "relics" "docker" "notify" "ntfy" "baseUrl"] ''
      stc.relics.docker.notify no longer speaks ntfy. Move your ntfy call into
      stc.relics.docker.notify.notifyCommand, which receives STC_NOTIFY_SERVICE
      and STC_NOTIFY_HOSTNAME in the environment.
    '')
    (lib.mkRemovedOptionModule ["stc" "relics" "docker" "notify" "ntfy" "topicFile"] ''
      stc.relics.docker.notify no longer speaks ntfy. Read the topic file inside
      stc.relics.docker.notify.notifyCommand instead (STC stays agnostic to the
      notification backend, like the *File secrets pattern).
    '')
  ];

  options.stc.relics.docker.notify = {
    enable = lib.mkEnableOption "Docker container failure notifications and unhealthy-container restarts";

    hostname = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "Hostname exposed to notifyCommand as STC_NOTIFY_HOSTNAME.";
    };

    watchLabel = lib.mkOption {
      type = lib.types.str;
      default = "stc.docker/health-watch";
      description = ''
        Docker label used to mark containers for health monitoring.
        Set this on each container you want watched:
          labels."stc.docker/health-watch" = "true";
      '';
    };

    notifyCommand = lib.mkOption {
      type = lib.types.lines;
      default = "";
      example = lib.literalExpression ''
        '''
          ''${pkgs.curl}/bin/curl -s \
            -H "Title: [$STC_NOTIFY_HOSTNAME] $STC_NOTIFY_SERVICE failed" \
            -d "$STC_NOTIFY_SERVICE entered failed state" \
            "https://ntfy.sh/$(cat ''${config.sops.secrets."ntfy/topic".path})"
        '''
      '';
      description = ''
        Shell snippet run when a watched service fails. Receives the failed
        service and the host through the environment:
          STC_NOTIFY_SERVICE   — the systemd service that entered failed state
          STC_NOTIFY_HOSTNAME  — value of the `hostname` option

        STC is agnostic to the notification backend: put your ntfy curl, webhook
        POST, e-mail, etc. here, and read any secret it needs from its own file
        (the same philosophy as the *File secrets pattern). Required when the
        relic is enabled.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.notifyCommand != "";
        message = ''
          stc.relics.docker.notify.enable is true but notifyCommand is empty.
          Set stc.relics.docker.notify.notifyCommand to the shell command that
          delivers the alert (it receives STC_NOTIFY_SERVICE and
          STC_NOTIFY_HOSTNAME in the environment).
        '';
      }
    ];

    systemd = {
      services =
        {
          "stc-notify-failure@" = {
            description = "STC: notification for failed service %i";
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${notifyScript} %i";
            };
          };
          "stc-docker-health-watch@" = {
            description = "STC: Docker health watch for container %i";
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${healthWatchScript} %i";
            };
          };
        }
        // builtins.listToAttrs (
          map (w: {
            name = w.unit;
            value = {
              unitConfig = {
                OnFailure = "stc-notify-failure@%p.service";
                StartLimitBurst = 3;
                StartLimitIntervalSec = "300s";
              };
              serviceConfig = {
                Restart = "on-failure";
                RestartSec = "30s";
              };
            };
          })
          watchedList
        );

      timers = builtins.listToAttrs (
        map (w: {
          name = "stc-docker-health-watch@${w.container}";
          value = {
            description = "STC: Docker health watch timer for ${w.container}";
            wantedBy = ["timers.target"];
            partOf = ["${w.unit}.service"];
            timerConfig = {
              OnBootSec = "240s";
              OnUnitActiveSec = "30s";
              Unit = "stc-docker-health-watch@${w.container}.service";
            };
          };
        })
        watchedList
      );
    };
  };
}
