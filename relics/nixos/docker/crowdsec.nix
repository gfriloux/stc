# Relic: docker-crowdsec
#
# Runs CrowdSec in a Docker container as a behavioral IDS/IPS layer.
# Reads Traefik access logs to detect and block malicious traffic. This is
# log-based behavioral detection, not a WAF: STC does not configure the CrowdSec
# AppSec component, so it does not inspect request bodies inline.
# Designed to work alongside stc.relics.docker.traefik (optional but common).
#
# Secrets: point stc.relics.docker.crowdsec.envFile at whatever your secrets
# provider materialises (sops-nix, agenix, etc.).
{
  config,
  lib,
  pkgs,
  options,
  ...
}: let
  cfg = config.stc.relics.docker.crowdsec;
  dockerLib = import ./_lib.nix;

  # Guarded on the option existing so this relic stays usable on its own:
  # the traefik relic declares stc.relics.docker.traefik only when imported.
  traefikEnabled =
    (options.stc.relics.docker ? traefik) && config.stc.relics.docker.traefik.enable;
  traefikCfg = config.stc.relics.docker.traefik;
in {
  imports = [
    (lib.mkRenamedOptionModule ["stc" "docker" "crowdsec" "enable"] ["stc" "relics" "docker" "crowdsec" "enable"])
    (lib.mkRenamedOptionModule ["stc" "docker" "crowdsec" "image"] ["stc" "relics" "docker" "crowdsec" "image"])
    (lib.mkRenamedOptionModule ["stc" "docker" "crowdsec" "dataDir"] ["stc" "relics" "docker" "crowdsec" "dataDir"])
    (lib.mkRenamedOptionModule ["stc" "docker" "crowdsec" "envFile"] ["stc" "relics" "docker" "crowdsec" "envFile"])
  ];

  options.stc.relics.docker.crowdsec = {
    enable = lib.mkEnableOption "CrowdSec IDS/IPS container";

    image = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "crowdsecurity/crowdsec:v1.7.8"; # renovate
      description = ''
        Docker image to use for CrowdSec. Required — STC ships no default so image
        versions live with the consumer, where your own renovate scans the right
        host. Set it in your host config, pinned by tag (and optionally digest):

          stc.relics.docker.crowdsec.image = "crowdsecurity/crowdsec:v1.7.8"; # renovate
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      description = "Base directory for CrowdSec data and config volumes.";
    };

    envFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Path to the environment file passed to the CrowdSec container.
        Point this at whatever your secrets provider materialises
        (e.g. config.sops.secrets."crowdsec/env".path).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.image != null;
        message = ''
          stc.relics.docker.crowdsec.enable is true but no image is set.
          STC ships no default image — set it in your host config, e.g.:
            stc.relics.docker.crowdsec.image = "crowdsecurity/crowdsec:v1.7.8"; # renovate
        '';
      }
    ];

    virtualisation.oci-containers.containers."crowdsec" = {
      inherit (cfg) image;
      serviceName = "crowdsec";

      environmentFiles = lib.optional (cfg.envFile != null) cfg.envFile;

      volumes =
        [
          "${cfg.dataDir}/data:/var/lib/crowdsec/data"
          "${cfg.dataDir}/etc:/etc/crowdsec"
        ]
        ++ lib.optional traefikEnabled
        "${traefikCfg.dataDir}/logs:/var/log/traefik:ro";

      extraOptions = dockerLib.mkHealthCheck {
        cmd = "wget -q -O /dev/null http://localhost:8080/health";
      };

      labels = {
        "traefik.enable" = "false";
        "stc.docker/health-watch" = "true";
      };

      networks = ["web"];
    };

    systemd = {
      tmpfiles.rules = [
        "d ${cfg.dataDir}/data 0750 0 0 -"
        "d ${cfg.dataDir}/etc 0750 0 0 -"
      ];

      # CrowdSec joins the "web" network. When Traefik is enabled it owns the
      # docker-network-web unit (and orders it before crowdsec too). When Traefik
      # is absent, CrowdSec must create the network itself, otherwise nothing
      # does — and it must start before the container that joins it.
      services = lib.mkIf (!traefikEnabled) {
        "docker-network-web" =
          dockerLib.mkNetwork pkgs "web"
          // {
            requiredBy = ["crowdsec.service"];
            before = ["crowdsec.service"];
          };
      };
    };
  };
}
