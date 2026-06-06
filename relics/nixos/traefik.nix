# Relic: traefik (native)
#
# Traefik v3 as the native NixOS service (`services.traefik`), for hosts that run
# services directly on the machine rather than in Docker. ACME uses the HTTP-01
# challenge (`httpChallenge` on the `web` entryPoint, port 80).
#
# STC ships a second, independent Traefik as a Docker container
# (`relics-docker-traefik`) for container workloads; it uses the TLS-ALPN-01
# challenge instead. The two are separate deployments — pick one per host. Both
# name their ACME resolver `letsencrypt`, so consumer dynamic configs are portable.
{
  config,
  lib,
  options,
  ...
}: let
  cfg = config.stc.relics.traefik;
in {
  imports = [
    (lib.mkRenamedOptionModule ["stc" "traefik" "enable"] ["stc" "relics" "traefik" "enable"])
    (lib.mkRenamedOptionModule ["stc" "traefik" "email"] ["stc" "relics" "traefik" "email"])
    (lib.mkRenamedOptionModule ["stc" "traefik" "logLevel"] ["stc" "relics" "traefik" "logLevel"])
  ];

  options.stc.relics.traefik = {
    enable = lib.mkEnableOption "Traefik reverse proxy (native NixOS service)";

    email = lib.mkOption {
      type = lib.types.str;
      description = "Email address used for Let's Encrypt ACME registration.";
    };

    logLevel = lib.mkOption {
      type = lib.types.enum ["DEBUG" "INFO" "WARN" "ERROR"];
      default = "INFO";
      description = "Traefik log level.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.traefik = {
      enable = true;

      staticConfigOptions = {
        entryPoints = {
          web = {
            address = ":80";
            asDefault = true;
            http.redirections.entrypoint = {
              to = "websecure";
              scheme = "https";
            };
          };
          websecure = {
            address = ":443";
            asDefault = true;
            http.tls.certResolver = "letsencrypt";
          };
        };

        log = {
          level = cfg.logLevel;
          filePath = "/var/lib/traefik/traefik.log";
          format = "json";
        };

        accessLog = {
          filePath = "/var/lib/traefik/access.log";
          format = "json";
          fields = {
            # Request fields (method, status, duration…) are safe to keep.
            defaultMode = "keep";
            # Headers are NOT safe to keep wholesale: Authorization and Cookie
            # would land in the persisted access.log (this proxy fronts Vaultwarden).
            # Drop everything and allowlist only non-sensitive diagnostic headers.
            headers = {
              defaultMode = "drop";
              names = {
                "User-Agent" = "keep";
                "X-Real-Ip" = "keep";
                "X-Forwarded-For" = "keep";
                "X-Forwarded-Proto" = "keep";
              };
            };
          };
        };

        certificatesResolvers.letsencrypt.acme = {
          inherit (cfg) email;
          httpChallenge.entryPoint = "web";
        };
      };
    };

    networking.firewall.allowedTCPPorts = [80 443];

    # /var/lib/traefik holds ACME certs — must survive reboots.
    # Only emitted when the impermanence relic is present (so Traefik stays
    # evaluable on its own — environment stays {} otherwise), and only active
    # when it is enabled. The persist root follows its configurable persistPath.
    environment = lib.optionalAttrs (options.stc.relics ? impermanence) {
      persistence.${config.stc.relics.impermanence.persistPath} = lib.mkIf config.stc.relics.impermanence.enable {
        directories = [
          {
            directory = "/var/lib/traefik";
            user = "traefik";
            group = "traefik";
            mode = "0700";
          }
        ];
      };
    };
  };
}
