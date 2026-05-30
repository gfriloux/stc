# Docker helper functions — pure, no pkgs dependency except mkNetwork.
# Exposed at the flake level as stc.lib.docker for consumer use.
# Also imported directly by sibling relic modules.
{
  # Build the --health-* flags list for extraOptions.
  mkHealthCheck =
    {
      cmd,
      interval ? "30s",
      timeout ? "10s",
      startPeriod ? "30s",
      retries ? 3,
    }:
    [
      "--health-cmd=${cmd}"
      "--health-interval=${interval}"
      "--health-timeout=${timeout}"
      "--health-start-period=${startPeriod}"
      "--health-retries=${toString retries}"
    ];

  # Idempotent Docker network systemd service.
  mkNetwork = pkgs: name: {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "${pkgs.docker}/bin/docker network rm -f ${name}";
    };
    script = ''
      docker network inspect ${name} || docker network create ${name}
    '';
  };
}
