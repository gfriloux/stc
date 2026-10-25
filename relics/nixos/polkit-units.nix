# Relic: polkit unit delegation
#
# Lets the members of a group start, stop or restart named systemd units
# without sudo. `sudo systemctl` grants every unit on the host; the usual need
# is "restart this one container", or start an on-demand service declared with
# `wantedBy = lib.mkForce []`.
#
# SECURITY-RELEVANT: this widens privileges by design. The default grants
# nothing, and every grant is three-way scoped: group, unit, verb.
#
# What systemd hands polkit (measured in the locked systemd source):
#   - org.freedesktop.systemd1.manage-units, with the details `unit` (the full
#     id, "foo.service") and `verb` ("start", "restart", …). Manager-level calls
#     (CancelJob, ResetFailed with no unit) ask for the same action with NO
#     details, so the rule tests both before using them.
#   - StartTransientUnit (systemd-run) asks the same action with the name the
#     CALLER chose and verb "start". systemd refuses a transient unit whose name
#     already has a unit file, and accepts any other. So a rule that matched a
#     name with no unit file — a prefix's future match, a typo, a disabled unit —
#     would let `systemd-run --unit=<that name> <anything>` run as root.
#     Measured in the proving before this was fixed. Hence every granted name is
#     resolved at build time against the units this configuration installs:
#     exact names must exist, prefixes expand to the matching declared units,
#     and the rule compares against that closed list only.
#   - Enable, disable, mask, link and preset go through
#     org.freedesktop.systemd1.manage-unit-files, which carries no unit at all.
#     It cannot be scoped: granting it lets a group link a unit file it wrote,
#     then start it as root. The relic never grants it.
#   - Freeze and thaw ask manage-units with verbs "stop" and "start", but
#     systemd's D-Bus policy refuses FreezeUnit/ThawUnit to unprivileged
#     callers before polkit is asked. Measured in the proving.
#   - The caller picks the job mode (`--job-mode=flush` cancels every queued
#     job on the host); polkit sees no mode, so no rule can restrict it. The
#     docs say so.
#
# One generated rule, data in, YES or nothing out. It never denies, but a YES
# here ends polkit's evaluation, so it wins over a rule read after it. It also
# stops consumers concatenating hand-written rules into
# security.polkit.extraConfig.
#
# Hardening: the hardening relic mounts /proc with hidepid=2. Measured in a
# test VM: the rule still grants, because polkit identifies the caller from
# D-Bus credentials. polkitd needs no extra group.
{
  config,
  lib,
  ...
}: let
  cfg = config.stc.relics.polkitUnits;

  # Job verbs only. kill, set-property, clean, bind-mount, … share the action id
  # but change what a unit does or delete its state.
  jobVerbs = [
    "start"
    "stop"
    "restart"
    "try-restart"
    "reload"
    "reload-or-restart"
    "reload-or-try-restart"
  ];

  unitTypes = ["service" "socket" "target" "timer" "path" "mount" "automount" "swap" "slice" "scope" "device"];

  # polkit sees "foo.service"; a bare "foo" would match nothing.
  fullUnitName = name:
    if lib.any (t: lib.hasSuffix ".${t}" name) unitTypes
    then name
    else "${name}.service";

  # Units this configuration installs: each has a unit file, so systemd will
  # not let a transient unit take its name.
  installed = lib.attrNames (lib.filterAttrs (_: u: u.enable) config.systemd.units);

  # An instance ("foo@bar.service") is installed when its template is.
  isInstalled = name: let
    m = builtins.match "([^@]+@).*(\\.[a-z]+)" name;
  in
    lib.elem name installed || (m != null && lib.elem (lib.concatStrings m) installed);

  resolve = d: let
    named = map fullUnitName d.units;
    prefixed = lib.filter (n: lib.any (p: lib.hasPrefix p n) d.unitPrefixes) installed;
  in {
    inherit named prefixed;
    missing = lib.filter (n: !isInstalled n) named;
    emptyPrefixes = lib.filter (p: !lib.any (lib.hasPrefix p) installed) d.unitPrefixes;
    units = lib.unique (named ++ prefixed);
  };

  rules =
    map (d: {
      inherit (d) group;
      inherit (resolve d) units;
      verbs = d.actions;
    })
    cfg.delegations;

  delegationType = lib.types.submodule {
    options = {
      group = lib.mkOption {
        type = lib.types.str;
        example = "wheel";
        description = "Members of this group receive the delegation.";
      };

      units = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["docker-immich-server" "docker-immich-redis"];
        description = ''
          Exact unit names, as systemd ids (not aliases). A name without a type
          suffix gets ".service". Each must be a unit this configuration
          installs (or an instance of an installed template), or the build
          fails: a name with no unit file could be claimed by systemd-run.
        '';
      };

      unitPrefixes = lib.mkOption {
        type = lib.types.listOf (lib.types.strMatching ".+");
        default = [];
        example = ["docker-immich-"];
        description = ''
          Unit id prefixes, expanded at build time to the units this
          configuration installs ("docker-immich-" →
          "docker-immich-server.service", …). Over-grants by construction: a
          unit added later with the prefix is included at the next rebuild, of
          any type. A prefix that matches nothing fails the build.
        '';
      };

      actions = lib.mkOption {
        type = lib.types.listOf (lib.types.enum jobVerbs);
        default = ["start" "stop" "restart"];
        description = ''
          systemctl verbs granted. Job verbs only; enabling or disabling a unit
          cannot be scoped to a unit, so it is never delegated.
        '';
      };
    };
  };
in {
  options.stc.relics.polkitUnits = {
    enable = lib.mkEnableOption "polkit delegation of named systemd units to groups";

    delegations = lib.mkOption {
      type = lib.types.listOf delegationType;
      default = [];
      description = ''
        Who may do what to which units. Empty grants nothing. Each entry needs
        at least one unit or prefix.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions =
      lib.concatMap (d: [
        {
          assertion = d.units != [] || d.unitPrefixes != [];
          message = "stc.relics.polkitUnits: the delegation to group \"${d.group}\" names no unit and no prefix.";
        }
        {
          assertion = config.users.groups ? ${d.group};
          message = "stc.relics.polkitUnits: group \"${d.group}\" is not declared in users.groups.";
        }
        {
          assertion = (resolve d).missing == [];
          message = ''
            stc.relics.polkitUnits: the delegation to group "${d.group}" names
            units this configuration does not install:
            ${lib.concatStringsSep ", " (resolve d).missing}.
            A granted name with no unit file can be claimed by
            `systemd-run --unit=<name>` and run anything as root. Declare the
            unit (systemd.services.<name>, or an empty one for a unit shipped
            by a package) or remove it from the list.
          '';
        }
        {
          assertion = (resolve d).emptyPrefixes == [];
          message = "stc.relics.polkitUnits: the delegation to group \"${d.group}\" has prefixes matching no installed unit: ${lib.concatStringsSep ", " (resolve d).emptyPrefixes}.";
        }
      ])
      cfg.delegations;

    # Without polkit every request is denied and the rule is never read.
    security.polkit.enable = true;

    security.polkit.extraConfig = lib.mkIf (cfg.delegations != []) ''
      // stc.relics.polkitUnits — generated, do not edit.
      polkit.addRule(function (action, subject) {
        if (action.id !== "org.freedesktop.systemd1.manage-units") {
          return;
        }
        var unit = action.lookup("unit");
        var verb = action.lookup("verb");
        // Manager-level calls carry no unit and no verb: not ours to grant.
        if (!unit || !verb) {
          return;
        }
        var delegations = ${builtins.toJSON rules};
        for (var i = 0; i < delegations.length; i++) {
          var d = delegations[i];
          if (d.verbs.indexOf(verb) < 0 || !subject.isInGroup(d.group)) {
            continue;
          }
          // A closed list, resolved at build time: never match by pattern here.
          if (d.units.indexOf(unit) >= 0) {
            return polkit.Result.YES;
          }
        }
      });
    '';
  };
}
