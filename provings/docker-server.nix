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
    # suppresses the eval-time assertion; it must NOT suppress the wiring, which is
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

    # docker guards: one container in each case. Placeholder images, never run;
    # the guards are evaluation-time warnings, read back in the script below.
    virtualisation.oci-containers.containers = {
      # Unlabelled bypasses: one public port, one raw socket. Each must warn.
      "stc-proving-exposed" = {
        image = "stc-proving/exposed:placeholder";
        ports = ["8080:80/tcp" "127.0.0.1:9090:90"];
        volumes = ["/var/run/docker.sock:/var/run/docker.sock:ro"];
      };
      # A port appended to STC's own Traefik: the exemption covers the relic's
      # 80/443 only, so this one must warn.
      "traefik".ports = ["8081:8080"];
      # The same bypasses, each with its reason. Must not warn.
      "stc-proving-declared" = {
        image = "stc-proving/declared:placeholder";
        ports = ["2525:25/tcp"];
        volumes = ["/run/docker.sock:/var/run/docker.sock"];
        labels = {
          "stc.docker/public-ports" = "SMTP, Traefik cannot front it";
          "stc.docker/raw-docker-socket" = "proving the opt-out";
        };
      };
    };
  };

  # Never started: the script reads its evaluated warnings only. The socket
  # proxy is declined, so Traefik falls back to the raw socket (must warn), and
  # a consumer container that merely carries the proxy's name gets no
  # exemption (must warn).
  nodes.noproxy = {
    imports = [self.nixosModules.cogitator-docker-server];
    stc.cogitator.docker-server.enable = true;
    stc.relics.docker.socketProxy.enable = false;
    stc.relics.docker.crowdsec.enable = false;
    stc.relics.docker.traefik.image = "stc-proving/traefik:placeholder";
    stc.relics.docker.traefik.acme.email = "ops@example.test";
    virtualisation.oci-containers.containers."docker-socket-proxy" = {
      image = "stc-proving/impostor:placeholder";
      volumes = ["/run/docker.sock:/var/run/docker.sock:ro"];
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

    # Also the counter-example for serverSurvivability and nixHousekeeping:
    # every assert on those relics below is checked red here. A plain `= false`
    # also proves the cogitator enables them with mkDefault, as documented.
    stc.relics.serverSurvivability.enable = false;
    stc.relics.nixHousekeeping.enable = false;
    # Counter-example for the docker guards: the same unlabelled bypass, with
    # the guards declined, warns about nothing.
    stc.relics.docker.guards.enable = false;
    virtualisation.oci-containers.containers."stc-proving-exposed" = {
      image = "stc-proving/exposed:placeholder";
      ports = ["8080:80/tcp"];
      volumes = ["/var/run/docker.sock:/var/run/docker.sock:ro"];
    };

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

    with subtest("the health-cmd-in-image opt-out satisfies the assertion, not the watch"):
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

    with subtest("a headless server reboots instead of waiting for a console"):
        # Each assert is paired with nocrowdsec, which has the relic off, so none
        # of them can pass on stock defaults. What is NOT asserted, deliberately:
        # `panic=1` and `boot.panic_on_fail` — the test harness puts both on
        # every test VM's cmdline — and RebootWatchdogSec, whose 10min is
        # systemd's own default.
        for node, on in [(machine, True), (nocrowdsec, False)]:
            state = node.succeed(
                "systemctl show -p LoadState --value emergency.service"
            ).strip()
            assert (state == "not-found") == on, f"{node.name}: emergency.service {state}"

            # Presence, not effect: the harness's own panic=1 is on the same
            # cmdline. What this proves is that STC put panic=30 there.
            cmdline = node.succeed("cat /proc/cmdline").split()
            assert ("panic=30" in cmdline) == on, f"{node.name}: {cmdline}"

            # The q35 test machine exposes iTCO_wdt, so systemd really arms a
            # device here; this is its own report, not our config echoed back.
            armed = node.execute(
                "journalctl -b -o cat _PID=1 "
                "| grep -q 'Watchdog running with a hardware timeout of 30s'"
            )[0] == 0
            assert armed == on, f"{node.name}: watchdog armed={armed}"

            sleep = node.succeed("systemd-analyze cat-config systemd/sleep.conf")
            assert ("AllowSuspend=no" in sleep) == on, f"{node.name}: {sleep}"
            assert ("AllowHibernation=no" in sleep) == on, f"{node.name}: {sleep}"

        # A test VM has no bootloader to read back, so the generation cap is
        # checked on the evaluated configs; the off node shows GRUB's default.
        assert ${toString nodes.machine.boot.loader.grub.configurationLimit} == 5
        assert ${toString nodes.machine.boot.loader.systemd-boot.configurationLimit} == 5
        assert ${toString nodes.nocrowdsec.boot.loader.grub.configurationLimit} != 5

    with subtest("the docker guards warn on bypasses and only on them"):
        # The nodes' evaluated warnings, as a Python list of strings. Only the
        # guards' messages start with 'Container "'.
        guarded = {
            machine: [
                w.splitlines()[0]
                for w in ${builtins.toJSON nodes.machine.warnings}
                if w.startswith('Container "')
            ],
            nocrowdsec: [
                w.splitlines()[0]
                for w in ${builtins.toJSON nodes.nocrowdsec.warnings}
                if w.startswith('Container "')
            ],
            "noproxy": [
                w.splitlines()[0]
                for w in ${builtins.toJSON nodes.noproxy.warnings}
                if w.startswith('Container "')
            ],
        }
        print(guarded[machine])
        # Exactly the unlabelled bypasses: not the labelled container, not
        # Traefik's own 80/443, not the socket-proxy's socket, not
        # 127.0.0.1:9090 — but the port a consumer appended to Traefik.
        assert sorted(guarded[machine]) == [
            'Container "stc-proving-exposed" mounts the raw Docker socket',
            'Container "stc-proving-exposed" publishes 8080:80/tcp on every',
            'Container "traefik" publishes 8081:8080 on every',
        ], guarded[machine]
        assert guarded[nocrowdsec] == [], guarded[nocrowdsec]
        # The exemptions follow the relics: with the proxy off, Traefik's own
        # raw-socket fallback warns, and so does a stand-in with the proxy's name.
        assert sorted(guarded["noproxy"]) == [
            'Container "docker-socket-proxy" mounts the raw Docker socket',
            'Container "traefik" mounts the raw Docker socket',
        ], guarded["noproxy"]

    with subtest("the state manifest names paths that exist"):
        # The manifest is descriptive, so the only thing worth proving is that
        # it describes the machine: every path it lists exists on the booted
        # node, and a relic that is off contributes nothing.
        # A JSON list of plain strings is also a Python list literal.
        import shlex
        manifests = {
            machine: ${builtins.toJSON (map (e: e.path) nodes.machine.stc.relics.state.paths)},
            nocrowdsec: ${builtins.toJSON (map (e: e.path) nodes.nocrowdsec.stc.relics.state.paths)},
        }
        # The one exception is the Traefik dynamic config: with no
        # dynamicConfigFile the consumer writes it by hand, so it is listed
        # (that is the point) but nothing on a fresh node creates it.
        by_hand = "/srv/docker/traefik/conf/traefik_dynamic.yml"
        for node, paths in manifests.items():
            assert by_hand in paths, f"{node.name}: {paths}"
            for path in paths:
                if path != by_hand:
                    node.succeed(f"test -e {shlex.quote(path)}")
        assert "/srv/docker/crowdsec/data" in manifests[machine], manifests[machine]
        assert not any("crowdsec" in p for p in manifests[nocrowdsec]), manifests[nocrowdsec]

    with subtest("the store and the journal stay bounded"):
        def show(node, unit, prop):
            return node.succeed(f"systemctl show -p {prop} --value {unit}").strip()

        for node, on in [(machine, True), (nocrowdsec, False)]:
            # The build-time pressure valve: nix.conf carries no min-free at all
            # on stock NixOS.
            conf = node.succeed("cat /etc/nix/nix.conf").splitlines()
            assert ("min-free = 5368709120" in conf) == on, f"{node.name}: min-free"
            assert ("max-free = 16106127360" in conf) == on, f"{node.name}: max-free"

            # Scheduled retention. nix-gc.service exists either way (nixpkgs
            # defines it whenever nix.enable); the timer and the 30-day window
            # are what the relic adds. keepDays is in the unit's script, as in
            # provings/vm.nix.
            has_timer = node.execute("systemctl cat nix-gc.timer")[0] == 0
            assert has_timer == on, f"{node.name}: nix-gc.timer present={has_timer}"
            script = node.succeed(
                f"cat {show(node, 'nix-gc.service', 'ExecStart').split('path=')[1].split()[0]}"
            )
            assert ("--delete-older-than 30d" in script) == on, f"{node.name}: {script}"

            # Builds yield: these are what systemd applied to the units, read
            # back from the manager, not the Nix options echoed.
            for unit, prop, want in [
                ("nix-daemon.service", "OOMScoreAdjust", "250"),
                ("nix-daemon.service", "CPUSchedulingPolicy", "3"),  # batch
                ("nix-daemon.service", "IOSchedulingPriority", "7"),  # stock: 4
                ("nix-gc.service", "CPUSchedulingPolicy", "3"),
            ]:
                got = show(node, unit, prop)
                assert (got == want) == on, f"{node.name}: {unit} {prop}={got}"
            io = show(node, "nix-gc.service", "IOSchedulingClass")
            assert (io == "3") == on, f"{node.name}: nix-gc IOSchedulingClass={io}"

            journald = node.succeed("systemd-analyze cat-config systemd/journald.conf")
            assert ("SystemMaxUse=500M" in journald) == on, f"{node.name}: {journald}"
            assert ("MaxRetentionSec=1month" in journald) == on, f"{node.name}: {journald}"
  '';
}
