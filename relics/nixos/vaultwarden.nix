{ config, lib, ... }:

let
  cfg = config.stc.vaultwarden;
in
{
  options.stc.vaultwarden = {
    enable = lib.mkEnableOption "Vaultwarden — unofficial Bitwarden-compatible server";

    hostname = lib.mkOption {
      type = lib.types.str;
      description = "Public domain name for Vaultwarden (used for the Traefik route).";
    };

    backup = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable periodic database backups to /var/backup/vaultwarden.";
    };

    signupsDomains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Restrict self-registration to these email domains. Empty list allows all domains.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.vaultwarden =
      {
        enable = true;

        config = {
          ROCKET_ADDRESS = "127.0.0.1";
          ROCKET_PORT = 8222;
          SIGNUPS_ALLOWED = true;
          INVITATIONS_ALLOWED = true;
          SHOW_PASSWORD_HINT = false;
          WEBSOCKET_ENABLED = true;
          LOG_LEVEL = "warn";
        } // lib.optionalAttrs (cfg.signupsDomains != [ ]) {
          SIGNUPS_DOMAINS_WHITELIST = lib.concatStringsSep "," cfg.signupsDomains;
        };
      }
      // lib.optionalAttrs cfg.backup {
        backupDir = "/var/backup/vaultwarden";
      };

    # Wire up the Traefik route if Traefik is enabled alongside Vaultwarden.
    services.traefik.dynamicConfigOptions = lib.mkIf config.services.traefik.enable {
      http = {
        routers.vaultwarden = {
          rule = "Host(`${cfg.hostname}`)";
          entryPoints = [ "websecure" ];
          service = "vaultwarden";
          tls.certResolver = "letsencrypt";
        };
        services.vaultwarden = {
          loadBalancer.servers = [ { url = "http://127.0.0.1:8222"; } ];
        };
      };
    };

    # Vaultwarden data must survive reboots.
    # Requires relics-impermanence (or any module that defines environment.persistence).
    environment.persistence."/persist".directories =
      [
        {
          directory = "/var/lib/vaultwarden";
          user = "vaultwarden";
          group = "vaultwarden";
          mode = "0700";
        }
      ]
      ++ lib.optionals cfg.backup [
        {
          directory = "/var/backup/vaultwarden";
          user = "vaultwarden";
          group = "vaultwarden";
          mode = "0700";
        }
      ];
  };
}
