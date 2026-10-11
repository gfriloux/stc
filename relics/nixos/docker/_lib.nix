# Docker helper functions — pure, no pkgs dependency except mkNetwork.
# Exposed at the flake level as stc.lib.docker for consumer use.
# Also imported directly by sibling relic modules.
{
  # Build the --health-* flags list for extraOptions.
  mkHealthCheck = {
    cmd,
    interval ? "30s",
    timeout ? "10s",
    startPeriod ? "30s",
    retries ? 3,
  }: [
    "--health-cmd=${cmd}"
    "--health-interval=${interval}"
    "--health-timeout=${timeout}"
    "--health-start-period=${startPeriod}"
    "--health-retries=${toString retries}"
  ];

  # Idempotent Docker network systemd service.
  #
  # No ExecStop: a restart of this unit (e.g. on nixos-rebuild) would otherwise
  # `docker network rm -f` the network out from under any attached container.
  # The network is cheap and idempotent to (re)create, so we never tear it down.
  #
  # The flip side of that choice: nothing here re-creates a network that was
  # removed behind our back, since RemainAfterExit keeps the unit "active". That
  # is why cogitator/nixos/docker-server.nix leaves `virtualisation.docker
  # .autoPrune` off — `docker system prune -f` deletes unused networks, and a
  # network whose containers have not attached yet counts as unused.
  mkNetwork = pkgs: name: {
    path = [pkgs.docker];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      docker network inspect ${pkgs.lib.escapeShellArg name} \
        || docker network create ${pkgs.lib.escapeShellArg name}
    '';
  };
}
