# Proving: polkit unit delegation relic
# Boots a VM with one delegation and drives systemctl as unprivileged users,
# checking each grant and each refusal against the three scopes the relic
# claims: group, unit, verb. No cogitator enables the relic, so the node imports
# it alone.
#
# Every check runs twice: as booted, and after /proc is remounted with
# hidepid=2,gid=proc — the mount the hardening relic sets, which the test
# framework's own fileSystems would otherwise replace. The relic claims it does
# not need to loosen hardening; this is where that claim is measured.
{self}: {
  name = "polkit-units";

  nodes.machine = {pkgs, ...}: let
    idle = {
      wantedBy = ["multi-user.target"];
      serviceConfig.ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
    };
  in {
    imports = [self.nixosModules.relics-polkit-units];

    stc.relics.polkitUnits = {
      enable = true;
      delegations = [
        {
          group = "ops";
          units = ["stc-named" "stc-tpl@one"];
          unitPrefixes = ["stc-prefixed-"];
        }
      ];
    };

    users.groups.ops = {};
    users.groups.proc = {};
    users.users.op = {
      isNormalUser = true;
      extraGroups = ["ops"];
    };
    users.users.stranger.isNormalUser = true;

    systemd.services.stc-named = idle;
    systemd.services.stc-prefixed-a = idle;
    systemd.services.stc-other = idle;
    systemd.services."stc-tpl@".serviceConfig.ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    for unit in ["stc-named", "stc-prefixed-a", "stc-other"]:
        machine.wait_for_unit(f"{unit}.service")


    def systemctl(user, args):
        return machine.execute(
            f"su {user} -s /bin/sh -c 'systemctl --no-ask-password {args}' 2>&1"
        )


    def systemctl_run(user, args):
        return machine.execute(
            f"su {user} -s /bin/sh -c 'systemd-run --no-ask-password {args}' 2>&1"
        )


    def granted(user, args):
        rc, out = systemctl(user, args)
        assert rc == 0, f"{user}: systemctl {args} refused: {out}"


    def refused(user, args):
        rc, out = systemctl(user, args)
        # A polkit refusal, not some unrelated failure.
        assert rc != 0 and "Access denied" in out, f"{user}: systemctl {args}: rc={rc} {out}"


    def check():
        with subtest("a member drives the named unit with the default verbs"):
            granted("op", "restart stc-named")
            granted("op", "stop stc-named")
            granted("op", "start stc-named")

        with subtest("a prefix covers a declared unit it was never told about"):
            granted("op", "restart stc-prefixed-a")

        with subtest("an instance of a declared template, by name"):
            granted("op", "start stc-tpl@one")
            granted("op", "stop stc-tpl@one")
            refused("op", "start stc-tpl@two")

        with subtest("freeze and thaw stay out of reach"):
            # systemd asks polkit with verb "stop" to freeze and "start" to
            # thaw, so the rule alone would grant them. systemd's D-Bus policy
            # does not let an unprivileged caller send FreezeUnit or ThawUnit,
            # and `systemctl freeze` first asks for the ungranted "ref" verb.
            refused("op", "freeze stc-named")
            for method in ["FreezeUnit", "ThawUnit"]:
                rc, out = machine.execute(
                    "su op -s /bin/sh -c 'busctl call org.freedesktop.systemd1"
                    " /org/freedesktop/systemd1 org.freedesktop.systemd1.Manager"
                    f" {method} s stc-named.service' 2>&1"
                )
                assert rc != 0 and "Access denied" in out, f"{method}: {out}"

        with subtest("each scope holds: unit, verb, group"):
            refused("op", "restart stc-other")
            refused("op", "reload-or-restart stc-named")
            refused("op", "kill stc-named")
            refused("stranger", "restart stc-named")
            machine.succeed("systemctl is-active stc-other")

        with subtest("a transient unit cannot borrow a delegated name"):
            # StartTransientUnit asks polkit with the caller's name and verb
            # "start": a name the rule matched would run any command as root.
            # Measured before the fix: stc-prefixed-evil ran as root. Names are
            # now resolved at build time; a declared name has a unit file,
            # which systemd refuses to hand to a transient unit.
            for name in ["stc-prefixed-evil", "stc-named", "stc-tpl@one"]:
                rc, out = systemctl_run("op", f"--unit={name} touch /run/stc-pwned")
                assert rc != 0, f"systemd-run --unit={name} succeeded: {out}"
                machine.fail("test -e /run/stc-pwned")

        with subtest("enable is never delegated"):
            refused("op", "enable stc-named")

        with subtest("a call with no unit is not granted"):
            # Manager-level ResetFailed asks polkit with no unit and no verb.
            refused("op", "reset-failed")
            # Refused either way; what the guard prevents is the rule throwing.
            # Measured without it: "Error evaluating admin rules: TypeError:
            # cannot read property 'indexOf' of undefined".
            # Positive control first: the journal does carry polkitd's lines.
            machine.succeed("journalctl -u polkit --no-pager | grep -q 'Started polkitd'")
            machine.fail("journalctl -u polkit --no-pager | grep -q 'Error evaluating'")


    check()
    machine.succeed("mount -o remount,hidepid=2,gid=proc /proc")
    assert "hidepid=invisible" in machine.succeed("findmnt -no OPTIONS /proc")
    check()
  '';
}
