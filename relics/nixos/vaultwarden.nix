{
  config,
  lib,
  options,
  ...
}: let
  cfg = config.stc.relics.vaultwarden;
in {
  imports = [
    (lib.mkRenamedOptionModule ["stc" "vaultwarden" "enable"] ["stc" "relics" "vaultwarden" "enable"])
    (lib.mkRenamedOptionModule ["stc" "vaultwarden" "hostname"] ["stc" "relics" "vaultwarden" "hostname"])
    (lib.mkRenamedOptionModule ["stc" "vaultwarden" "backup"] ["stc" "relics" "vaultwarden" "backup"])
    (lib.mkRenamedOptionModule ["stc" "vaultwarden" "signupsDomains"] ["stc" "relics" "vaultwarden" "signupsDomains"])
    (lib.mkRenamedOptionModule ["stc" "vaultwarden" "showPasswordHint"] ["stc" "relics" "vaultwarden" "showPasswordHint"])
  ];

  options.stc.relics.vaultwarden = {
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

    signupsAllowed = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Allow new user self-registration. Disabled by default — enable only if you intend to expose registration to users.";
    };

    invitationsAllowed = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Allow organization invitations. Disabled by default.";
    };

    signupsDomains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Restrict self-registration to these email domains. Empty list allows all domains. Only has effect when signupsAllowed = true.";
    };

    showPasswordHint = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Show password hints on the login page. Disabled by default for security.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.vaultwarden =
      {
        enable = true;

        config =
          {
            ROCKET_ADDRESS = "127.0.0.1";
            ROCKET_PORT = 8222;
            SIGNUPS_ALLOWED = cfg.signupsAllowed;
            INVITATIONS_ALLOWED = cfg.invitationsAllowed;
            SHOW_PASSWORD_HINT = cfg.showPasswordHint;
            WEBSOCKET_ENABLED = true;
            LOG_LEVEL = "warn";
          }
          // lib.optionalAttrs (cfg.signupsDomains != []) {
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
          entryPoints = ["websecure"];
          service = "vaultwarden";
          tls.certResolver = "letsencrypt";
        };
        services.vaultwarden = {
          loadBalancer.servers = [{url = "http://127.0.0.1:8222";}];
        };
      };
    };

    # Vaultwarden data must survive reboots.
    # Only emitted when the impermanence relic is present (so Vaultwarden stays
    # evaluable on its own — environment stays {} otherwise), and only active
    # when it is enabled. The persist root follows its configurable persistPath.
    environment = lib.optionalAttrs (options.stc.relics ? impermanence) {
      persistence.${config.stc.relics.impermanence.persistPath} = lib.mkIf config.stc.relics.impermanence.enable {
        directories =
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
    };
  };
}
