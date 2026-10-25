# Proving: heartbeat relic
# Boots a VM with a local HTTP stub standing in for the receiver (Uptime Kuma,
# healthchecks.io) and three watched oneshots, and checks the one claim that
# matters: a ping arrives when the job succeeded, and only then.
#
# The sharpest case is a long-running service stopped midway: systemd counts
# its SIGTERM as a clean end, the unit ends "inactive" with Result=success, and
# OnSuccess= fires — so without the relic's gate it would ping. (A oneshot
# stopped midway ends failed instead, and never triggers OnSuccess=; measured.)
# No cogitator enables the relic, so the node imports it alone.
{self}: {
  name = "heartbeat";

  nodes.machine = {pkgs, ...}: let
    oneshot = cmd: {
      serviceConfig.Type = "oneshot";
      script = cmd;
    };
    # Records every requested path, answers 200.
    stub = pkgs.writers.writePython3 "stc-heartbeat-stub" {} ''
      import http.server


      class Handler(http.server.BaseHTTPRequestHandler):
          def do_GET(self):
              with open("/run/stc-heartbeat-hits", "a") as hits:
                  hits.write(self.path + "\n")
              self.send_response(200)
              self.end_headers()


      http.server.HTTPServer(("127.0.0.1", 8000), Handler).serve_forever()
    '';
    url = name: pkgs.writeText "url-${name}" "http://127.0.0.1:8000/${name}-SECRET";
  in {
    imports = [self.nixosModules.relics-heartbeat];

    stc.relics.heartbeat = {
      enable = true;
      units = {
        stc-hb-ok.urlFile = "${url "ok"}";
        stc-hb-fail.urlFile = "${url "fail"}";
        stc-hb-slow.urlFile = "${url "slow"}";
        stc-hb-daemon.urlFile = "${url "daemon"}";
        stc-hb-declared.urlFile = "${url "declared"}";
      };
    };

    systemd.services = {
      stc-hb-ok = oneshot "true";
      stc-hb-fail = oneshot "false";
      stc-hb-slow = oneshot "sleep 300";
      # Exit 3, declared a success by the unit itself.
      stc-hb-declared = oneshot "exit 3" // {serviceConfig.SuccessExitStatus = "3";};
      # A long-running service. systemd counts SIGTERM on stop as a clean end
      # for it, so a stop leaves Result=success and does trigger OnSuccess=.
      stc-hb-daemon.serviceConfig.ExecStart = "${pkgs.coreutils}/bin/sleep 300";
      stc-hb-stub.serviceConfig.ExecStart = stub;
    };
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.succeed("systemctl start stc-hb-stub")
    machine.wait_for_open_port(8000)


    def hits():
        return machine.succeed("cat /run/stc-heartbeat-hits 2>/dev/null || true")


    with subtest("a successful run pings"):
        machine.succeed("systemctl start stc-hb-ok")
        machine.wait_until_succeeds("grep -qx /ok-SECRET /run/stc-heartbeat-hits")

    with subtest("a status the unit declares a success pings"):
        machine.succeed("systemctl start stc-hb-declared")
        machine.wait_until_succeeds("grep -qx /declared-SECRET /run/stc-heartbeat-hits")

    with subtest("starting the heartbeat by hand does not ping"):
        # No OnSuccess= trigger, so no MONITOR_* snapshot: the gate refuses.
        before = hits().count("/ok-SECRET")
        machine.succeed("systemctl start stc-heartbeat-stc-hb-ok")
        machine.succeed(
            "journalctl -u stc-heartbeat-stc-hb-ok --no-pager | grep -q 'did not succeed'"
        )
        assert hits().count("/ok-SECRET") == before, hits()

    with subtest("a failed run does not ping"):
        machine.fail("systemctl start stc-hb-fail")
        machine.succeed("systemctl is-failed stc-hb-fail")
        machine.sleep(5)
        assert "/fail-SECRET" not in hits(), hits()

    with subtest("a oneshot stopped midway fails, so it does not ping"):
        machine.succeed("systemctl start --no-block stc-hb-slow")
        machine.wait_until_succeeds("test $(systemctl show -P ActiveState stc-hb-slow) = activating")
        machine.succeed("systemctl stop stc-hb-slow")
        assert machine.succeed("systemctl show -P Result stc-hb-slow").strip() == "signal"
        machine.sleep(5)
        assert "/slow-SECRET" not in hits(), hits()

    with subtest("a service stopped midway ends 'success', and the gate holds"):
        machine.succeed("systemctl start stc-hb-daemon")
        machine.wait_until_succeeds("test $(systemctl show -P ActiveState stc-hb-daemon) = active")
        machine.succeed("systemctl stop stc-hb-daemon")
        # This is the case OnSuccess= alone gets wrong: Result says success,
        # OnSuccess= fires, and only the gate's check of the exit keeps it quiet.
        assert machine.succeed("systemctl show -P Result stc-hb-daemon").strip() == "success"
        machine.wait_until_succeeds(
            "journalctl -u stc-heartbeat-stc-hb-daemon --no-pager | grep -q 'did not succeed'"
        )
        assert "/daemon-SECRET" not in hits(), hits()

    with subtest("an unreachable receiver never fails the watched job"):
        machine.succeed("systemctl stop stc-hb-stub")
        machine.succeed("systemctl start stc-hb-ok")
        machine.wait_until_succeeds("systemctl is-failed stc-heartbeat-stc-hb-ok")
        assert machine.succeed("systemctl show -P Result stc-hb-ok").strip() == "success"

    with subtest("the URL stays out of unit files and scripts"):
        unit = machine.succeed("systemctl cat stc-heartbeat-stc-hb-ok")
        script = machine.succeed(
            "cat $(systemctl show -P ExecStart stc-heartbeat-stc-hb-ok | grep -o '/nix/store/[^ ;]*')"
        )
        assert "SECRET" not in unit + script, unit + script
  '';
}
