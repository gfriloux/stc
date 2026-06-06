# Relic: docker-crowdsec
#
# Runs CrowdSec in a Docker container as a WAF/IDS layer.
# Reads Traefik access logs to detect and block malicious traffic.
# Designed to work alongside stc.relics.docker.traefik (optional but common).
#
# Secrets: point stc.relics.docker.crowdsec.envFile at whatever your secrets
# provider materialises (sops-nix, agenix, etc.).
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.stc.relics.docker.crowdsec;
  dockerLib = import ./_lib.nix;
  traefikCfg = config.stc.relics.docker.traefik;
in {
  imports = [
    (lib.mkRenamedOptionModule ["stc" "docker" "crowdsec" "enable"] ["stc" "relics" "docker" "crowdsec" "enable"])
    (lib.mkRenamedOptionModule ["stc" "docker" "crowdsec" "image"] ["stc" "relics" "docker" "crowdsec" "image"])
    (lib.mkRenamedOptionModule ["stc" "docker" "crowdsec" "dataDir"] ["stc" "relics" "docker" "crowdsec" "dataDir"])
    (lib.mkRenamedOptionModule ["stc" "docker" "crowdsec" "envFile"] ["stc" "relics" "docker" "crowdsec" "envFile"])
  ];

  options.stc.relics.docker.crowdsec = {
    enable = lib.mkEnableOption "CrowdSec WAF container";

    image = lib.mkOption {
      type = lib.types.str;
      default = "crowdsecurity/crowdsec:v1.7.8";
      description = "Docker image to use for CrowdSec.";
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
    virtualisation.oci-containers.containers."crowdsec" = {
      inherit (cfg) image;
      serviceName = "crowdsec";

      environmentFiles = lib.optional (cfg.envFile != null) cfg.envFile;

      volumes =
        [
          "${cfg.dataDir}/data:/var/lib/crowdsec/data"
          "${cfg.dataDir}/etc:/etc/crowdsec"
        ]
        ++ lib.optional traefikCfg.enable
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

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir}/data 0750 0 0 -"
      "d ${cfg.dataDir}/etc 0750 0 0 -"
    ];
  };
}
