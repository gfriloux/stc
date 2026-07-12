# Cogitator: docker-server
#
# Full Docker reverse-proxy stack: Traefik + CrowdSec WAF, with optional failure
# notifications. Enabling this is equivalent to enabling
# stc.relics.docker.{traefik,socketProxy,crowdsec} individually — use those
# directly if you need finer control.
#
# You still need to supply the machine-specific options:
#   stc.relics.docker.traefik.image = "traefik:v3.7.6"; # renovate
#   stc.relics.docker.traefik.acme.email = "you@example.com";
#   stc.relics.docker.crowdsec.image = "crowdsecurity/crowdsec:v1.7.8"; # renovate
#   stc.relics.docker.crowdsec.dataDir = "/srv/docker/crowdsec";
#
# Notifications are opt-in (off by default). To enable them, supply a transport:
#   stc.cogitator.docker-server.notify.enable = true;
#   stc.relics.docker.notify.notifyCommand = "…";  # reads STC_NOTIFY_SERVICE / _HOSTNAME
{
  config,
  lib,
  ...
}: let
  cfg = config.stc.cogitator.docker-server;
in {
  imports = [
    ../../relics/nixos/docker/traefik.nix
    ../../relics/nixos/docker/socket-proxy.nix
    ../../relics/nixos/docker/crowdsec.nix
    ../../relics/nixos/docker/notify.nix
  ];

  options.stc.cogitator.docker-server = {
    enable = lib.mkEnableOption "STC Docker server stack (Traefik + CrowdSec)";

    notify.enable =
      lib.mkEnableOption "container failure notifications for the stack"
      // {
        description = ''
          Enable the docker-notify relic for this stack. Off by default so the
          stack boots without forcing a notification transport; when enabled you
          must set stc.relics.docker.notify.notifyCommand.
        '';
      };
  };

  config = lib.mkIf cfg.enable {
    stc.relics.docker = {
      traefik.enable = true;
      # Secure default: Traefik reaches the Docker API through the filtering
      # socket-proxy instead of bind-mounting the raw socket.
      socketProxy.enable = true;
      crowdsec.enable = true;
      notify.enable = cfg.notify.enable;
    };

    virtualisation = {
      docker = {
        enable = true;
        autoPrune.enable = true;
      };
      oci-containers.backend = "docker";
    };
  };
}
