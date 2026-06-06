{ config, lib, ... }:

let
  cfg = config.stc.relics.traefik;
in
{
  imports = [
    (lib.mkRenamedOptionModule [ "stc" "traefik" "enable" ] [ "stc" "relics" "traefik" "enable" ])
    (lib.mkRenamedOptionModule [ "stc" "traefik" "email" ] [ "stc" "relics" "traefik" "email" ])
    (lib.mkRenamedOptionModule [ "stc" "traefik" "logLevel" ] [ "stc" "relics" "traefik" "logLevel" ])
  ];

  options.stc.relics.traefik = {
    enable = lib.mkEnableOption "Traefik reverse proxy (native NixOS service)";

    email = lib.mkOption {
      type = lib.types.str;
      description = "Email address used for Let's Encrypt ACME registration.";
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [ "DEBUG" "INFO" "WARN" "ERROR" ];
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
          email = cfg.email;
          httpChallenge.entryPoint = "web";
        };
      };
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];

    # /var/lib/traefik holds ACME certs — must survive reboots.
    # Requires relics-impermanence (or any module that defines environment.persistence).
    environment.persistence."/persist".directories = [
      {
        directory = "/var/lib/traefik";
        user = "traefik";
        group = "traefik";
        mode = "0700";
      }
    ];
  };
}
