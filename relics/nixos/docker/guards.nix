# Relic: docker-guards
#
# Evaluation-time warnings for containers that step around the protections the
# other docker relics put in place, which a green build would otherwise hide:
#
#   - A port published on every interface ("3000:8080", "0.0.0.0:3000:8080").
#     Docker's DNAT and FORWARD rules sit ahead of networking.firewall, so the
#     port is reachable from the Internet whatever the firewall declares —
#     skipping Traefik, TLS and the CrowdSec middleware.
#   - A raw Docker socket mount (/run/docker.sock or /var/run/docker.sock,
#     `:ro` or not: read-only does not make the API read-only). That is host
#     root, whatever relics-docker-socket-proxy promises.
#
# A container that means it says why, with a label whose value is the reason:
#   labels."stc.docker/public-ports" = "SMTP, Traefik cannot front it";
#   labels."stc.docker/raw-docker-socket" = "needs exec and restart (nixos#100)";
#
# STC's own containers are exempt where the bypass IS their job, computed from
# the relics that declare them rather than labelled (a label is part of the
# container definition, and adding one would restart them on every host):
# traefik's own 80/443 while relics-docker-traefik is on — only those two
# entries, since `ports` is a list a consumer can append to — and
# docker-socket-proxy's socket while relics-docker-socket-proxy is on.
# Traefik's own raw-socket fallback, used when the proxy is off, is NOT exempt:
# it is a proxy bypass.
#
# Out of scope: `-p`, `-v` and `--mount` in extraOptions (not how
# oci-containers declares ports and volumes), and `--network=host` (the host's
# own stack serves the port, so the NixOS firewall applies).
#
# Warnings for now (#101); promoting them to assertions waits for the known
# consumer to be clean, as #61 → #77 did.
{
  config,
  lib,
  ...
}: let
  cfg = config.stc.relics.docker.guards;
  docker = config.stc.relics.docker;

  publicPortsLabel = "stc.docker/public-ports";
  rawSocketLabel = "stc.docker/raw-docker-socket";

  # Docker short syntax: [ADDRESS:]HOST:CONTAINER[/PROTO], or CONTAINER alone,
  # which publishes on a random host port. Only the three-part form carries an
  # address; IPv6 addresses come in brackets.
  isPublic = port: let
    spec = lib.head (lib.splitString "/" port);
    m = builtins.match "(\\[[^]]*]|[^:]*):([^:]*):([^:]+)" spec;
  in
    # Any IPv6 spelling of "every address" ([::], [::0], [0:0:…:0]).
    m == null || lib.elem (lib.head m) ["" "0.0.0.0"] || builtins.match "\\[[0:]*]" (lib.head m) != null;

  # The socket itself, or the whole directory that holds it.
  socketPaths = ["/run/docker.sock" "/var/run/docker.sock" "/run" "/run/" "/var/run" "/var/run/"];
  mountsSocket = volume: lib.elem (lib.head (lib.splitString ":" volume)) socketPaths;

  optedOut = c: label: (c.labels.${label} or "") != "";

  # The Traefik relic's own entries (relics/nixos/docker/traefik.nix). Kept in
  # step by the docker-server proving: a drift there makes Traefik warn.
  exemptPorts = lib.optionalAttrs (docker.traefik.enable or false) {
    traefik = ["80:80/tcp" "443:443/tcp"];
  };
  exemptSocket = lib.optional (docker.socketProxy.enable or false) "docker-socket-proxy";

  containers = config.virtualisation.oci-containers.containers;

  publicPorts =
    lib.filterAttrs (_: ps: ps != [])
    (lib.mapAttrs (n: c:
      if optedOut c publicPortsLabel
      then []
      else lib.filter isPublic (lib.subtractLists (exemptPorts.${n} or []) c.ports))
    containers);

  socketMounts =
    lib.filterAttrs (_: vs: vs != [])
    (lib.mapAttrs (n: c:
      if lib.elem n exemptSocket || optedOut c rawSocketLabel
      then []
      else lib.filter mountsSocket c.volumes)
    containers);
in {
  options.stc.relics.docker.guards.enable =
    lib.mkEnableOption "warnings for containers that publish on every interface or mount the raw Docker socket";

  config = lib.mkIf cfg.enable {
    warnings =
      lib.optional (config.virtualisation.oci-containers.backend != "docker") ''
        stc.relics.docker.guards is enabled but
        virtualisation.oci-containers.backend is
        "${config.virtualisation.oci-containers.backend}", so it checks nothing:
        the guards cover the docker backend only.
      ''
      ++ lib.optionals (config.virtualisation.oci-containers.backend == "docker") (
        lib.mapAttrsToList (name: ports: ''
          Container "${name}" publishes ${lib.concatStringsSep ", " ports} on every
          interface. Docker's own iptables rules come before networking.firewall,
          so this port is open to the Internet whatever the firewall says, and it
          skips Traefik, TLS and CrowdSec.

          Pick the one that is true:
            - route it through Traefik and drop `ports`;
            - bind it to loopback or a private address:
                ports = ["127.0.0.1:<host port>:<container port>"];
            - or, if it must be public, say why:
                labels."${publicPortsLabel}" = "<reason>";
        '')
        publicPorts
        ++ lib.mapAttrsToList (name: volumes: ''
          Container "${name}" mounts the raw Docker socket
          (${lib.concatStringsSep ", " volumes}). That is root on the host, `:ro`
          or not, and it bypasses relics-docker-socket-proxy.

          Pick the one that is true:
            - reach the API through the proxy instead:
                DOCKER_HOST=tcp://docker-socket-proxy:2375, on its network;
            - or, if it needs what the proxy cannot give, say why:
                labels."${rawSocketLabel}" = "<reason>";
        '')
        socketMounts
      );
  };
}
