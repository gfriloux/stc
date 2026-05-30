# Cogitator: docker-server
#
# Full Docker reverse-proxy stack: Traefik + CrowdSec WAF + failure notifications.
# Enabling this is equivalent to enabling stc.docker.{traefik,crowdsec,notify}
# individually — use those directly if you need finer control.
#
# You still need to supply the machine-specific options:
#   stc.docker.traefik.acme.email = "you@example.com";
#   stc.docker.crowdsec.dataDir = "/srv/docker/crowdsec";
#   stc.docker.notify.ntfy.topicFile = config.sops.secrets."ntfy/topic".path;
{ config, lib, ... }:
let
  cfg = config.stc.cogitator.docker-server;
in
{
  imports = [
    ../../relics/nixos/docker/traefik.nix
    ../../relics/nixos/docker/crowdsec.nix
    ../../relics/nixos/docker/notify.nix
  ];

  options.stc.cogitator.docker-server = {
    enable = lib.mkEnableOption "STC Docker server stack (Traefik + CrowdSec + ntfy notifications)";
  };

  config = lib.mkIf cfg.enable {
    stc.docker = {
      traefik.enable = true;
      crowdsec.enable = true;
      notify.enable = true;
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
