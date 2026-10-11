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
    # Declaring this turns ON validation of @file middleware references, so the
    # node below exercises the opt-in path and not just the default-off one.
    stc.relics.docker.traefik.fileMiddlewares = ["crowdsec@file"];
    stc.relics.docker.crowdsec.dataDir = "/srv/docker/crowdsec";
    stc.relics.docker.notify.notifyCommand = "true";

    # A watched container whose HEALTHCHECK lives in its image. The opt-out label
    # suppresses the eval-time warning; it must NOT suppress the wiring, which is
    # what this node asserts below. It also exercises the serviceName fallback
    # (unit = docker-<name>) that traefik/crowdsec never reach, since both set
    # serviceName explicitly.
    virtualisation.oci-containers.containers."stc-proving-img-health" = {
      image = "stc-proving/img-health:placeholder";
      labels = {
        "stc.docker/health-watch" = "true";
        "stc.docker/health-cmd-in-image" = "true";
      };
    };

    # A routed container on the *valid* side of the Traefik reference
    # validation, covering all three paths at once: the certresolver the relic
    # declares, a middleware declared by labels and referenced unqualified
    # (docker provider), and a middleware referenced as @file and declared in
    # fileMiddlewares. Without it the assertions would be "green" purely
    # because nothing exercises them.
    virtualisation.oci-containers.containers."stc-proving-app" = {
      image = "stc-proving/app:placeholder";
      labels = {
        "traefik.enable" = "true";
        "traefik.http.routers.proving-app.rule" = "Host(`app.example.test`)";
        "traefik.http.routers.proving-app.tls.certresolver" = "letsencrypt";
        "traefik.http.routers.proving-app.middlewares" = "proving-headers,crowdsec@file";
        "traefik.http.middlewares.proving-headers.headers.frameDeny" = "true";
      };
    };
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

    with subtest("no autoPrune timer — it would delete those networks at boot"):
        # virtualisation.docker.autoPrune is off in this profile, so nixpkgs
        # instantiates no docker-prune.timer at all (the .service exists but is
        # never triggered, having no startAt). A timer here would mean a missed
        # weekly window fires `docker system prune -f` while the containers are
        # still starting, removing their networks for good.
        machine.fail("systemctl cat docker-prune.timer")
        assert "docker-prune.timer" not in machine.succeed(
            "systemctl list-timers --all --no-legend --no-pager"
        )

    with subtest("notify hook is wired on the watched units"):
        # Only labelled containers (traefik, crowdsec) opt into the health-watch;
        # the socket-proxy carries no watch label and must stay unwired.
        assert "OnFailure=stc-notify-failure@" in machine.succeed("systemctl cat traefik.service")
        assert "OnFailure=stc-notify-failure@" in machine.succeed("systemctl cat crowdsec.service")
        machine.succeed("systemctl cat stc-notify-failure@.service")
        machine.succeed("systemctl cat stc-docker-health-watch@traefik.timer")
        machine.succeed("systemctl cat stc-docker-health-watch@crowdsec.timer")
        machine.fail("systemctl cat stc-docker-health-watch@docker-socket-proxy.timer")

    with subtest("the health-cmd-in-image opt-out silences the warning, not the watch"):
        # The label only tells evaluation "the healthcheck is in the image, I
        # checked". A container carrying it stays fully watched — if this ever
        # stops holding, consumers would silently lose monitoring by documenting
        # their intent, which is the opposite of the point.
        machine.succeed("systemctl cat stc-docker-health-watch@stc-proving-img-health.timer")
        assert "OnFailure=stc-notify-failure@" in machine.succeed(
            "systemctl cat docker-stc-proving-img-health.service"
        )

    with subtest("traefik reference validation is exercised on the valid side"):
        # The assertions are eval-time, so this VM existing at all is the proof
        # that they passed. What this subtest guards is the *coverage*: assert
        # the labels really reach the container, so a later edit to this node
        # cannot quietly stop exercising the check and leave a false green.
        script = start_script("docker-stc-proving-app")
        for label in [
            "traefik.http.routers.proving-app.tls.certresolver=letsencrypt",
            "traefik.http.routers.proving-app.middlewares=proving-headers,crowdsec@file",
            "traefik.http.middlewares.proving-headers.headers.frameDeny=true",
        ]:
            assert label in script, f"label {label} is missing from the start script"

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
