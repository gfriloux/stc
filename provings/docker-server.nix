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

    # nixos-test-base.nix defaults system.switch.enable to false (a Hydra
    # optimisation: don't pull switch-to-configuration into every test). The
    # pre-switch checks are *invoked* by that binary, so without this the
    # subtests below would have nothing to run and the guard would be unproven.
    system.switch.enable = true;

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

  # A function, so the script below can reach the generated pre-switch checks.
  # Second node, added with issue #86: CrowdSec declined, and deliberately given
  # no image.
  #
  # This locks in the sharpest claim of that chantier. The docker relics assert
  # on a missing image, so while the cogitator pinned crowdsec.enable at normal
  # priority a consumer who did not want CrowdSec still had to hand it an image
  # — they were made to configure a service they were trying not to run. Now the
  # enablement is mkDefault and a plain `= false` removes the assertion with it.
  #
  # The plainness and the absent image are both load-bearing. Re-pin
  # crowdsec.enable, or move an image reference out from behind the relic's own
  # enable guard, and this node stops evaluating — which is the regression this
  # exists to catch.
  nodes.nocrowdsec = {
    imports = [self.nixosModules.cogitator-docker-server];

    stc.cogitator.docker-server.enable = true;
    stc.relics.docker.crowdsec.enable = false;

    # Everything the rest of the stack needs, and nothing for CrowdSec.
    stc.relics.docker.traefik.image = "stc-proving/traefik:placeholder";
    stc.relics.docker.socketProxy.image = "stc-proving/socket-proxy:placeholder";
    stc.relics.docker.traefik.acme.email = "ops@example.test";
  };

  testScript = {nodes, ...}: ''
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

    with subtest("pre-switch checks are live, and the guard is not a tautology"):
        # Validity first: the guard sorts itself out of the way when
        # /run/booted-system is absent, which is how it stays compatible with
        # the nixos-anywhere install flow. If it were absent HERE, every assert
        # below would pass for the wrong reason.
        machine.succeed("test -e /run/booted-system")

        # `check` runs the pre-switch checks and returns without activating
        # anything, so these subtests cannot disturb the ones above.
        machine.succeed("/run/current-system/bin/switch-to-configuration check")

    with subtest("the guard tolerates a runtime FQDN"):
        # systemd may have set the FQDN rather than the short name, which a
        # strict comparison would read as the wrong host. Set through /proc —
        # the very value the guard reads — so the subtest does not depend on
        # hostnamed's state. And set at runtime rather than via
        # networking.domain, which would prove nothing: nixpkgs writes only
        # cfg.hostName into /etc/hostname, so declaring a domain does not make
        # the kernel hostname an FQDN. A name overwritten at runtime by DHCP or
        # cloud-init is the real scenario anyway.
        machine.succeed("echo machine.example.test > /proc/sys/kernel/hostname")
        machine.succeed("/run/current-system/bin/switch-to-configuration check")

    with subtest("the guard aborts when the closure belongs to another host"):
        machine.succeed("echo other-machine > /proc/sys/kernel/hostname")
        out = machine.fail("/run/current-system/bin/switch-to-configuration check 2>&1")
        assert "refusing to activate the closure of 'machine'" in out, out
        assert "NIXOS_NO_CHECK=1" in out, out

    with subtest("NIXOS_NO_CHECK=1 really is the escape hatch"):
        # Proven, not assumed: it is the only variable that survives
        # nixos-rebuild's `env -i`, so the documented way out has to work.
        machine.succeed(
            "NIXOS_NO_CHECK=1 /run/current-system/bin/switch-to-configuration check"
        )
        machine.succeed("echo machine > /proc/sys/kernel/hostname")

    with subtest("the closure diff can never abort a switch"):
        # Make dix fail for real by handing the script a closure path that does
        # not exist, instead of trusting that `|| echo` is enough. The guard
        # still passes (the hostname is restored), so a non-zero exit here could
        # only come from the diff.
        machine.succeed(
            "${nodes.machine.config.system.preSwitchChecksScript} /nonexistent-closure switch"
        )

    with subtest("CrowdSec can be declined without being given an image"):
        # That this node evaluated at all is the regression guard: the docker
        # relics assert on a missing image, so while the cogitator pinned
        # crowdsec.enable a consumer who did not want CrowdSec still had to hand
        # it one. Re-pin the enablement and this node stops building.
        #
        # Booting it too, so the claim is not merely an evaluation: the rest of
        # the stack must still be wired on a host that declined one relic.
        nocrowdsec.wait_for_unit("multi-user.target")

        # Unit names measured, not guessed: the container units are `crowdsec`
        # and `traefik`, and the pair discriminates — listing systemd.services
        # with the relic enabled yields `crowdsec`, and declining it removes
        # exactly that one while `traefik` and `docker-socket-proxy` stay.
        nocrowdsec.fail("systemctl cat crowdsec.service")
        nocrowdsec.succeed("systemctl cat traefik.service")
        nocrowdsec.succeed("systemctl cat docker-socket-proxy.service")
  '';
}
