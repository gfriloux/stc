# Relic: docker-traefik
#
# Runs Traefik v3 in a Docker container as a reverse proxy.
# Auto-generates the static config from Nix options.
# The dynamic config (routes, middlewares) is supplied at runtime via dynamicConfigFile.
#
# This is the container deployment. STC also ships a native Traefik
# (`relics-traefik`, services.traefik) for non-Docker hosts. They are separate —
# pick one per host. This one uses the TLS-ALPN-01 challenge (`tlsChallenge`)
# rather than the native's HTTP-01, but both name their resolver `letsencrypt`.
#
# When stc.relics.docker.crowdsec.enable = true, the CrowdSec bouncer plugin is
# automatically wired into the static config and traefik waits for crowdsec.
#
# Secrets: point stc.relics.docker.traefik.dynamicConfigFile at whatever your
# secrets provider materialises.
{
  config,
  lib,
  pkgs,
  options,
  ...
}: let
  cfg = config.stc.relics.docker.traefik;
  dockerLib = import ./_lib.nix;

  # Guarded on the option existing so this relic stays usable on its own:
  # the crowdsec relic declares stc.relics.docker.crowdsec only when imported.
  crowdsecEnabled =
    (options.stc.relics.docker ? crowdsec) && config.stc.relics.docker.crowdsec.enable;

  # When the socket-proxy relic is enabled, Traefik talks to the Docker API over
  # TCP through the filtering proxy instead of bind-mounting the raw socket.
  # Guarded on the option existing so this relic stays usable on its own.
  socketProxyEnabled =
    (options.stc.relics.docker ? socketProxy) && config.stc.relics.docker.socketProxy.enable;
  socketProxyNetwork = config.stc.relics.docker.socketProxy.network;
  # Inserted raw after the heredoc strips its common indent, so this carries the
  # already-stripped (4-space) indentation to sit under the docker provider.
  dockerProviderEndpoint = lib.optionalString socketProxyEnabled "\n    endpoint: \"tcp://docker-socket-proxy:2375\"";

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
      letsencrypt:
        acme:
          email: "${cfg.acme.email}"
          storage: "acme.json"
          tlsChallenge: {}

    providers:
      docker:
        watch: true
        network: web${dockerProviderEndpoint}
      file:
        filename: "/etc/traefik/traefik_dynamic.yml"
    ${crowdsecPlugin}
  '';
in {
  imports = [
    (lib.mkRenamedOptionModule ["stc" "docker" "traefik" "enable"] ["stc" "relics" "docker" "traefik" "enable"])
    (lib.mkRenamedOptionModule ["stc" "docker" "traefik" "image"] ["stc" "relics" "docker" "traefik" "image"])
    (lib.mkRenamedOptionModule ["stc" "docker" "traefik" "dataDir"] ["stc" "relics" "docker" "traefik" "dataDir"])
    (lib.mkRenamedOptionModule ["stc" "docker" "traefik" "acme" "email"] ["stc" "relics" "docker" "traefik" "acme" "email"])
    (lib.mkRenamedOptionModule ["stc" "docker" "traefik" "enableDashboard"] ["stc" "relics" "docker" "traefik" "enableDashboard"])
    (lib.mkRenamedOptionModule ["stc" "docker" "traefik" "dynamicConfigFile"] ["stc" "relics" "docker" "traefik" "dynamicConfigFile"])
  ];

  options.stc.relics.docker.traefik = {
    enable = lib.mkEnableOption "Traefik reverse proxy container";

    image = lib.mkOption {
      type = lib.types.str;
      default = "traefik:v3.7.1@sha256:6b9cbca6fac42ab0075f5437d8dc1685cfd188626d8d515839ea94f8b6271c42";
      description = ''
        Docker image to use for Traefik. Pinned by digest (the tag is kept for
        readability; the digest is authoritative). The same reasoning as the
        socket proxy applies: when socketProxy.enable = false this container
        mounts the raw Docker socket, so a silently-swapped image is exactly as
        dangerous here. Multi-arch index digest — resolve a new one with
        `skopeo inspect --format '{{.Digest}}' docker://traefik:<tag>`.
      '';
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
      default = false;
      description = ''
        Enable the Traefik API dashboard. Off by default to keep the attack
        surface minimal on production servers.

        Note: the dashboard listens on the in-container `traefik` entrypoint
        (127.0.0.1:8080). That is the container's own loopback, and the port is
        not published, so enabling this alone does not expose it — and an SSH
        tunnel to the host cannot reach it either, since the host loopback is not
        the container's. To reach it, publish the port or add a dynamic-config
        route to the dashboard service.
      '';
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
      inherit (cfg) image;
      serviceName = "traefik";

      volumes =
        # Bind-mount the raw socket only when NOT going through the socket-proxy.
        lib.optional (!socketProxyEnabled) "/run/docker.sock:/var/run/docker.sock:ro"
        ++ [
          "${cfg.dataDir}/acme.json:/acme.json"
          "${cfg.dataDir}/logs:/logs"
        ]
        ++ (
          if cfg.dynamicConfigFile != null
          then [
            "${cfg.dataDir}/conf/traefik.yml:/etc/traefik/traefik.yml"
            "${cfg.dynamicConfigFile}:/etc/traefik/traefik_dynamic.yml"
          ]
          else [
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

      networks = ["web"] ++ lib.optional socketProxyEnabled socketProxyNetwork;
    };

    services.logrotate.settings.traefik = {
      files = "${cfg.dataDir}/logs/traefik.log";
      frequency = "daily";
      rotate = 14;
      compress = true;
      delaycompress = true;
      missingok = true;
      notifempty = true;
      # No copytruncate: it leaves a window where log lines written during the
      # copy are lost — lines CrowdSec would otherwise tail, so missed attacks.
      # Instead, rotate by rename and tell Traefik to reopen its log (USR1).
      postrotate = "${pkgs.docker}/bin/docker kill -s USR1 traefik || true";
    };

    networking.firewall.allowedTCPPorts = [
      80
      443
    ];

    systemd = {
      services = {
        "traefik" = let
          crowdsecDep = lib.optional crowdsecEnabled "crowdsec.service";
          socketDep = lib.optional socketProxyEnabled "docker-socket-proxy.service";
          deps = crowdsecDep ++ socketDep;
        in
          lib.mkIf (deps != []) {
            after = deps;
            # The socket-proxy is load-bearing for Traefik's Docker provider, so
            # it stays a hard requirement. CrowdSec is only a Wants: an IDS/IPS
            # that fails (and gets `docker kill`ed by the health-watch) must not
            # drag the reverse proxy — and everything it serves — down with it.
            requires = socketDep;
            wants = crowdsecDep;
          };
        "docker-network-web" =
          dockerLib.mkNetwork pkgs "web"
          // {
            # Traefik (and CrowdSec, when enabled) joins the "web" network at
            # startup. Without ordering, on the first boot a consumer can race
            # ahead of network creation and fail. requiredBy + before guarantee
            # the network exists before every consumer, not just Traefik.
            requiredBy = ["traefik.service"] ++ lib.optional crowdsecEnabled "crowdsec.service";
            before = ["traefik.service"] ++ lib.optional crowdsecEnabled "crowdsec.service";
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
