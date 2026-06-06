# Relic: docker-notify
#
# Sends ntfy push notifications when a watched Docker container fails,
# and restarts unhealthy containers automatically.
#
# Containers opt in by setting the label defined in stc.relics.docker.notify.watchLabel.
# The relic then wires systemd OnFailure + a health-watch timer for each one.
#
# Secrets: point stc.relics.docker.notify.ntfy.topicFile at the file containing
# the ntfy topic name (one line, no newline required).
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.stc.relics.docker.notify;

  notifyScript = pkgs.writeShellScript "stc-notify-failure" ''
    SERVICE="$1"
    NTFY_TOPIC=$(cat ${cfg.ntfy.topicFile})

    ${pkgs.curl}/bin/curl -s \
      -H "Title: [${cfg.hostname}] $SERVICE failed" \
      -d "$SERVICE entered failed state" \
      "${cfg.ntfy.baseUrl}/$NTFY_TOPIC"
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
    (lib.mkRenamedOptionModule ["stc" "docker" "notify" "ntfy" "baseUrl"] ["stc" "relics" "docker" "notify" "ntfy" "baseUrl"])
    (lib.mkRenamedOptionModule ["stc" "docker" "notify" "ntfy" "topicFile"] ["stc" "relics" "docker" "notify" "ntfy" "topicFile"])
  ];

  options.stc.relics.docker.notify = {
    enable = lib.mkEnableOption "Docker container failure notifications via ntfy";

    hostname = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "Hostname shown in notification titles.";
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

    ntfy = {
      baseUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://ntfy.sh";
        description = ''
          ntfy server base URL (without trailing slash).

          The default is the public ntfy.sh: failure notifications (hostname and
          failed service names) leave your network to a third party, and the topic
          is the only secret — anyone who guesses it can read your alerts. For
          anything sensitive, self-host ntfy and/or use a long random topic.
        '';
      };

      topicFile = lib.mkOption {
        type = lib.types.str;
        description = ''
          Path to a file containing the ntfy topic name.
          Point this at whatever your secrets provider materialises
          (e.g. config.sops.secrets."ntfy/topic".path).
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
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
