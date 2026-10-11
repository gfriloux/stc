# Cogitator: docker-server
#
# Full Docker reverse-proxy stack: Traefik + CrowdSec WAF, with optional failure
# notifications. Enabling this is equivalent to enabling
# stc.relics.docker.{traefik,socketProxy,crowdsec} individually — use those
# directly if you need finer control.
#
# You still need to supply the machine-specific options (images are required —
# STC ships no defaults; pin them in your host so renovate scans the right repo):
#   stc.relics.docker.traefik.image = "traefik:v3.7.6"; # renovate
#   stc.relics.docker.traefik.acme.email = "you@example.com";
#   stc.relics.docker.socketProxy.image = "tecnativa/docker-socket-proxy:0.3.0"; # renovate
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
    ../../relics/nixos/pre-switch-checks.nix
  ];

  options.stc.cogitator.docker-server = {
    enable =
      lib.mkEnableOption "STC Docker server stack (Traefik + CrowdSec)"
      // {
        description = ''
          Enable the STC Docker server stack: Traefik, socket-proxy and CrowdSec,
          plus the pre-switch checks relic — on a remotely deployed host, refusing
          to activate another host's closure is part of the profile, not an extra.
        '';
      };

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

    # A Docker server is the shape this guards: a remote host, deployed with a
    # command that differs from its neighbour's by one flake attribute. Activate
    # the wrong closure here and you get wrong containers, wrong Traefik routers,
    # wrong users, wrong secrets — and no diff printed to warn you, because
    # `nixos-rebuild --target-host` shows none.
    stc.relics.preSwitchChecks.enable = true;

    virtualisation = {
      docker = {
        enable = true;

        # autoPrune is left OFF deliberately — it can take the whole stack down
        # at boot. `autoPrune.persistent` defaults to true and
        # `randomizedDelaySec` to "0", so a timer whose weekly window was missed
        # (unplanned reboot, machine off for a while) fires immediately once
        # docker.service is up — while the containers are still starting. At that
        # instant the networks this profile creates have nothing attached, so
        # `docker system prune -f` removes them as unused; the containers then
        # fail on `network not found` until StartLimitBurst and stay down.
        # Recovery is not automatic: mkNetwork (relics/nixos/docker/_lib.nix) is
        # a RemainAfterExit oneshot with no ExecStop, so nothing re-creates them.
        # The same hazard exists, more rarely, for a container that is stopped or
        # crashlooping when the weekly prune fires — which is why `persistent =
        # false` alone is not enough and the default is off outright.
        # Unused images grow the disk gradually and visibly; losing the network
        # of every container is an outage. A host that wants the cleanup sets:
        #   virtualisation.docker.autoPrune = { enable = true; persistent = false; };
        autoPrune.enable = lib.mkDefault false;
      };
      oci-containers.backend = "docker";
    };
  };
}
