# Relic: docker-traefik
#
# Runs Traefik v3 in a Docker container as a reverse proxy.
# Auto-generates the static config from Nix options.
# The dynamic config (routes, middlewares) is supplied at runtime via dynamicConfigFile.
#
# When stc.relics.docker.crowdsec.enable = true, the CrowdSec bouncer plugin is
# automatically wired into the static config and traefik waits for crowdsec.
#
# Secrets: point stc.relics.docker.traefik.dynamicConfigFile at whatever your
# secrets provider materialises.
{ config, lib, pkgs, ... }:
let
  cfg = config.stc.relics.docker.traefik;
  dockerLib = import ./_lib.nix;

  crowdsecEnabled = config.stc.relics.docker.crowdsec.enable;

  crowdsecPlugin = lib.optionalString crowdsecEnabled ''

    experimental:
      plugins:
        bouncer:
          moduleName: "github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin"
          version: "v1.5.1"
  '';

  staticConfig = pkgs.writeText "traefik.yml" ''
    entryPoints:
      web:
        address: ":80"
        http:
          redirections:
            entryPoint:
              to: websecure
              scheme: https

      websecure:
        address: ":443"
        transport:
          respondingTimeouts:
            readTimeout: 600s
            idleTimeout: 600s

      traefik:
        address: "127.0.0.1:8080"

    api:
      dashboard: ${lib.boolToString cfg.enableDashboard}

    ping:
      entryPoint: traefik

    accessLog:
      filePath: "/logs/traefik.log"
      format: json
      fields:
        headers:
          defaultMode: drop
          names:
            User-Agent: keep
            X-Real-Ip: keep
            X-Forwarded-For: keep
            X-Forwarded-Proto: keep

    certificatesResolvers:
      lets-encrypt:
        acme:
          email: "${cfg.acme.email}"
          storage: "acme.json"
          tlsChallenge: {}

    providers:
      docker:
        watch: true
        network: web
      file:
        filename: "/etc/traefik/traefik_dynamic.yml"
    ${crowdsecPlugin}
  '';
in
{
  imports = [
    (lib.mkRenamedOptionModule [ "stc" "docker" "traefik" "enable" ] [ "stc" "relics" "docker" "traefik" "enable" ])
    (lib.mkRenamedOptionModule [ "stc" "docker" "traefik" "image" ] [ "stc" "relics" "docker" "traefik" "image" ])
    (lib.mkRenamedOptionModule [ "stc" "docker" "traefik" "dataDir" ] [ "stc" "relics" "docker" "traefik" "dataDir" ])
    (lib.mkRenamedOptionModule [ "stc" "docker" "traefik" "acme" "email" ] [ "stc" "relics" "docker" "traefik" "acme" "email" ])
    (lib.mkRenamedOptionModule [ "stc" "docker" "traefik" "enableDashboard" ] [ "stc" "relics" "docker" "traefik" "enableDashboard" ])
    (lib.mkRenamedOptionModule [ "stc" "docker" "traefik" "dynamicConfigFile" ] [ "stc" "relics" "docker" "traefik" "dynamicConfigFile" ])
  ];

  options.stc.relics.docker.traefik = {
    enable = lib.mkEnableOption "Traefik reverse proxy container";

    image = lib.mkOption {
      type = lib.types.str;
      default = "traefik:v3.7.1";
      description = "Docker image to use for Traefik.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/srv/docker/traefik";
      description = "Base directory for Traefik data (logs, acme.json, conf).";
    };

    acme.email = lib.mkOption {
      type = lib.types.str;
      description = "Email address used for Let's Encrypt ACME registration.";
    };

    enableDashboard = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the Traefik API dashboard on 127.0.0.1:8080. Disable to reduce attack surface on production servers.";
    };

    dynamicConfigFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Path to the Traefik dynamic config file (traefik_dynamic.yml).
        Point this at whatever your secrets provider materialises.
        If null, an empty placeholder is used — add the file manually.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.containers."traefik" = {
      image = cfg.image;
      serviceName = "traefik";

      volumes =
        [
          "/run/docker.sock:/var/run/docker.sock"
          "${cfg.dataDir}/acme.json:/acme.json"
          "${cfg.dataDir}/logs:/logs"
        ]
        ++ (
          if cfg.dynamicConfigFile != null then
            [
              "${cfg.dataDir}/conf/traefik.yml:/etc/traefik/traefik.yml"
              "${cfg.dynamicConfigFile}:/etc/traefik/traefik_dynamic.yml"
            ]
          else
            [
              "${cfg.dataDir}/conf/traefik.yml:/etc/traefik/traefik.yml"
              "${cfg.dataDir}/conf/traefik_dynamic.yml:/etc/traefik/traefik_dynamic.yml"
            ]
        );

      extraOptions = dockerLib.mkHealthCheck {
        cmd = "traefik healthcheck";
        startPeriod = "10s";
      };

      labels = {
        "traefik.enable" = "false";
        "stc.docker/health-watch" = "true";
      };

      ports = [
        "80:80/tcp"
        "443:443/tcp"
      ];

      networks = [ "web" ];
    };

    services.logrotate.settings.traefik = {
      files = "${cfg.dataDir}/logs/traefik.log";
      frequency = "daily";
      rotate = 14;
      compress = true;
      delaycompress = true;
      missingok = true;
      notifempty = true;
      copytruncate = true;
    };

    networking.firewall.allowedTCPPorts = [
      80
      443
    ];

    systemd = {
      services = {
        "traefik" = lib.mkIf crowdsecEnabled {
          after = [ "crowdsec.service" ];
          requires = [ "crowdsec.service" ];
        };
        "docker-network-web" = dockerLib.mkNetwork pkgs "web" // {
          wantedBy = [ "traefik.service" ];
        };
      };
      tmpfiles.rules = [
        "d ${cfg.dataDir}/logs 0750 0 0 -"
        "d ${cfg.dataDir}/conf 0750 0 0 -"
        "f ${cfg.dataDir}/acme.json 0600 0 0 -"
        "L+ ${cfg.dataDir}/conf/traefik.yml - - - - ${staticConfig}"
      ];
    };
  };
}
