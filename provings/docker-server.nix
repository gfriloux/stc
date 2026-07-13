# Proving: docker-server cogitator
# Boots a VM with stc.cogitator.docker-server enabled and asserts the reusable
# *wiring* the relics generate — units, networks, health flags, notify hook, and
# the rendered Traefik static config.
#
# Scope note — this proving asserts wiring, NOT running containers. A nixosTest
# VM is network-isolated, so `docker pull` cannot succeed; the container services
# (traefik/crowdsec/docker-socket-proxy) never come up. That is fine: STC owns the
# wiring, not the image lifecycle. We therefore feed placeholder images (never
# pulled) and inspect the generated unit files with `systemctl cat`, which reads
# them from disk regardless of runtime state. Container start-up is deliberately
# not awaited.
{self}: {
  name = "docker-server";

  nodes.machine = {
    imports = [self.nixosModules.cogitator-docker-server];

    stc.cogitator.docker-server = {
      enable = true;
      notify.enable = true;
    };

    # Placeholder images — required by the relics, never pulled in the isolated VM.
    stc.relics.docker.traefik.image = "stc-proving/traefik:placeholder";
    stc.relics.docker.socketProxy.image = "stc-proving/socket-proxy:placeholder";
    stc.relics.docker.crowdsec.image = "stc-proving/crowdsec:placeholder";

    # Machine-specific values the stack needs to evaluate.
    stc.relics.docker.traefik.acme.email = "ops@example.test";
    stc.relics.docker.crowdsec.dataDir = "/srv/docker/crowdsec";
    stc.relics.docker.notify.notifyCommand = "true";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # oci-containers renders `docker run …` into a generated start script that
    # ExecStart points at; the image and extraOptions live inside that script,
    # not in the unit file. Resolve and read it.
    def start_script(svc):
        path = machine.succeed(
            f"systemctl show -p ExecStart --value {svc}.service "
            "| grep -oE '/nix/store/[^ ;]+start[^ ;]*' | head -1"
        ).strip()
        return machine.succeed(f"cat {path}")

    with subtest("container start scripts carry their pinned image"):
        for svc, image in [
            ("traefik", "stc-proving/traefik:placeholder"),
            ("crowdsec", "stc-proving/crowdsec:placeholder"),
            ("docker-socket-proxy", "stc-proving/socket-proxy:placeholder"),
        ]:
            assert image in start_script(svc), f"{svc} start script is missing its image {image}"

    with subtest("healthcheck flags are wired into the watched containers"):
        assert "--health-cmd" in start_script("traefik")
        assert "--health-cmd" in start_script("crowdsec")

    with subtest("docker networks have their creation units"):
        machine.succeed("systemctl cat docker-network-web.service")
        machine.succeed("systemctl cat docker-network-socket-proxy.service")

    with subtest("notify hook is wired on the watched units"):
        # Only labelled containers (traefik, crowdsec) opt into the health-watch;
        # the socket-proxy carries no watch label and must stay unwired.
        assert "OnFailure=stc-notify-failure@" in machine.succeed("systemctl cat traefik.service")
        assert "OnFailure=stc-notify-failure@" in machine.succeed("systemctl cat crowdsec.service")
        machine.succeed("systemctl cat stc-notify-failure@.service")
        machine.succeed("systemctl cat stc-docker-health-watch@traefik.timer")
        machine.succeed("systemctl cat stc-docker-health-watch@crowdsec.timer")
        machine.fail("systemctl cat stc-docker-health-watch@docker-socket-proxy.timer")

    with subtest("traefik static config is rendered, with the crowdsec bouncer plugin"):
        machine.wait_for_file("/srv/docker/traefik/conf/traefik.yml")
        static = machine.succeed("cat /srv/docker/traefik/conf/traefik.yml")
        assert "entryPoints:" in static
        # crowdsec is enabled, so its bouncer plugin must be injected.
        assert "crowdsec-bouncer-traefik-plugin" in static
        # socket-proxy is enabled, so Traefik talks to the API over TCP.
        assert "tcp://docker-socket-proxy:2375" in static
  '';
}
