# Relic: docker-socket-proxy
#
# Runs tecnativa/docker-socket-proxy: a filtering proxy in front of the Docker
# socket. The raw /run/docker.sock is mounted read-only into THIS container
# only; other containers (e.g. Traefik) talk to the Docker API over TCP through
# the proxy, which whitelists only the endpoints they need and blocks writes.
#
# Why this exists: mounting the socket with :ro into a container does NOT make
# the Docker API read-only. The :ro flag applies to the filesystem node, not the
# protocol — a process can still POST to the API (create a privileged container,
# i.e. root on the host). The proxy is the real mitigation: POST is disabled and
# only the GET endpoints listed in `permissions` are forwarded.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.stc.relics.docker.socketProxy;
  dockerLib = import ./_lib.nix;

  # bool -> "1"/"0" for the proxy's env-var API toggles.
  toFlag = b:
    if b
    then "1"
    else "0";
in {
  options.stc.relics.docker.socketProxy = {
    enable = lib.mkEnableOption "filtering proxy in front of the Docker socket";

    image = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "tecnativa/docker-socket-proxy:0.3.0"; # renovate
      description = ''
        Docker image to use for the socket proxy. Required — STC ships no default
        so image versions live with the consumer, where your own renovate scans
        the right host. This container holds the Docker socket, so pin it (tag and
        optionally digest):

          stc.relics.docker.socketProxy.image = "tecnativa/docker-socket-proxy:0.3.0"; # renovate
      '';
    };

    network = lib.mkOption {
      type = lib.types.str;
      default = "socket-proxy";
      description = ''
        Docker network shared between the proxy and its clients (e.g. Traefik).
        Clients reach the filtered Docker API at tcp://docker-socket-proxy:2375
        on this network.
      '';
    };

    permissions = lib.mkOption {
      type = lib.types.attrsOf lib.types.bool;
      default = {
        CONTAINERS = true;
        NETWORKS = true;
        EVENTS = true;
        PING = true;
        VERSION = true;
      };
      description = ''
        Docker API sections to expose, mapped to the proxy's env-var toggles
        (https://github.com/Tecnativa/docker-socket-proxy). The defaults cover
        exactly what the Traefik docker provider needs. Write access (POST) is
        always forced off — that is the whole point of the proxy.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.image != null;
        message = ''
          stc.relics.docker.socketProxy.enable is true but no image is set.
          STC ships no default image — set it in your host config, e.g.:
            stc.relics.docker.socketProxy.image = "tecnativa/docker-socket-proxy:0.3.0"; # renovate
        '';
      }
    ];

    virtualisation.oci-containers.containers."docker-socket-proxy" = {
      inherit (cfg) image;
      serviceName = "docker-socket-proxy";

      # The raw socket is exposed to the proxy only, read-only.
      volumes = ["/run/docker.sock:/var/run/docker.sock:ro"];

      # Enable the whitelisted GET sections; never POST.
      environment =
        (lib.mapAttrs (_: toFlag) cfg.permissions)
        // {
          POST = "0";
        };

      networks = [cfg.network];
    };

    # Dedicated network bridging the proxy to its clients, created before the
    # proxy so the container can join it on first boot.
    systemd.services."docker-network-${cfg.network}" =
      dockerLib.mkNetwork pkgs cfg.network
      // {
        requiredBy = ["docker-socket-proxy.service"];
        before = ["docker-socket-proxy.service"];
      };
  };
}
