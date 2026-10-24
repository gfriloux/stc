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
    ../../relics/nixos/server-survivability.nix
    ../../relics/nixos/nix-housekeeping.nix
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
      # traefik stays at normal priority: a reverse-proxied container host is
      # what this profile *is*, and the socket-proxy wiring lives inside that
      # relic. Declining it means wanting a different profile.
      traefik.enable = true;

      # Secure default: Traefik reaches the Docker API through the filtering
      # socket-proxy instead of bind-mounting the raw socket.
      #
      # mkDefault, because "default" is exactly what the line above claims to
      # be. Same for crowdsec: both are additive — measured, with either forced
      # off the profile evaluates and stays coherent.
      #
      # "Additive" is not "free" for the proxy, and the relic says what happens:
      # with it off, relics/nixos/docker/traefik.nix falls back to bind-mounting
      # /run/docker.sock read-only into the Traefik container. So declining it
      # trades a filtered API for direct read-only access to the Docker socket,
      # and a container escape there is host root. Before the demotion the
      # conflict forced the consumer to confront that; now the documentation
      # has to, which is why the docs page spells it out rather than presenting
      # the switch as cost-free.
      #
      # What this fixes is sharper than a priority detail. These relics assert
      # on a missing image ("stc.relics.docker.crowdsec.enable is true but no
      # image is set"), so a consumer who did not want CrowdSec still had to
      # hand CrowdSec an image — made to configure a service they were trying
      # not to run, with mkForce as the only way out.
      socketProxy.enable = lib.mkDefault true;
      crowdsec.enable = lib.mkDefault true;

      notify.enable = cfg.notify.enable;
    };

    # A Docker server is the shape this guards: a remote host, deployed with a
    # command that differs from its neighbour's by one flake attribute. Activate
    # the wrong closure here and you get wrong containers, wrong Traefik routers,
    # wrong users, wrong secrets — and no diff printed to warn you, because
    # `nixos-rebuild --target-host` shows none.
    # mkDefault: the guard is worth having on by default, and it is still
    # additive — a consumer who deploys through something other than
    # nixos-rebuild, or who runs the equivalent check in their own pipeline, can
    # decline it. Measured: forced off, the profile evaluates and stays coherent.
    stc.relics.preSwitchChecks.enable = lib.mkDefault true;

    # A remote host with no one at the console: reboot rather than wait. Additive,
    # so mkDefault — a consumer with IPMI or a KVM-over-IP may prefer the
    # emergency shell, and every sub-behaviour also has its own switch.
    stc.relics.serverSurvivability.enable = lib.mkDefault true;

    # A long-lived host: bound the store and the journal, and let builds yield
    # to what the machine serves. Additive, so mkDefault.
    stc.relics.nixHousekeeping.enable = lib.mkDefault true;

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
