# Ledger — plan: .claude/plans/v0.20.0/polkit-units.md

Pre-flight: issue #63 read; systemd's polkit calls read in the locked source
(`src/core/dbus-util.c`, `dbus-unit.c`, `dbus-manager.c`); a spike test VM
with a hand-written rule, before and after hidepid=2.

Step 1: Premise corrected: **the issue says one action id covers
start/stop/restart and enable/disable. It does not**: enable/disable are
`manage-unit-files`, which carries no unit. The user's earlier `allowEnable`
decision rested on that premise; asked again, they chose to drop it.

Step 1: Ruling: **`actions` is an enum of job verbs** (`start`, `stop`,
`restart`, `try-restart`, `reload`, `reload-or-restart`,
`reload-or-try-restart`). `kill`, `set-property`, `clean`, `bind-mount` and
the rest share the action id but are not lifecycle: `set-property` and
`bind-mount` change what the unit does, `clean` deletes its state. Adding
one later is an enum value.

Step 1: Ruling: **a unit name without a type suffix gets `.service`**,
because polkit sees the full id and `docker-immich-server` would otherwise
match nothing. Prefixes are matched against the full id as written.

Step 1: Ruling: **the relic sets `security.polkit.enable = true` at normal
priority.** Delegation is impossible without polkit; a consumer forcing it
off gets a conflict, which is the right answer.

Step 1: Ruling: **hardening untouched.** Measured, not assumed: hidepid=2
does not stop the rule, so polkitd joins no group.

Step 2: `relics/nixos/polkit-units.nix`, registered as `relics-polkit-units`.
Measured by eval: a delegation naming no unit and no prefix, and an undeclared
group, fail their assertions; an empty prefix and the verb `enable` fail the
option types; the generated data reads
`units = ["docker-a.service" "b.timer"]` for `["docker-a" "b.timer"]`.

Step 3: `provings/polkit-units.nix`, in the registry and the `test` recipe.
Green on the first run, before and after `hidepid=2,gid=proc`. The
no-unit check did not discriminate on its own (the call is refused with or
without the guard), so the guard was measured: without it, a spike rule made
polkit log `Error evaluating admin rules: TypeError: cannot read property
'indexOf' of undefined`. The proving now asserts no "Error evaluating" in
polkit's journal.

Step 4: `relics/polkit-units.md` EN + FR (privilege caution, three scopes,
units vs prefixes with the template-instance caveat, why no enable, rule
shape, hardening, proving); relics index row and link; provings index now
thirteen provings, nineteen boots, with a coverage row.

Closing review (fresh context):
- **C1, Critical, confirmed by measurement.** `StartTransientUnit`
  (systemd-run) asks `manage-units` with the caller's name and verb "start";
  systemd accepts any name without a unit file. The proving, extended first
  and run against the unfixed relic, failed: `systemd-run
  --unit=stc-prefixed-evil` ran ("Running as unit: stc-prefixed-evil.service").
  Fix: names are resolved at build time against
  `config.systemd.units` (enabled only). Exact names must be installed (or be
  an instance of an installed template); prefixes expand to installed units;
  a prefix matching nothing fails the build; the rule compares against the
  closed list only. Six eval cases measured (prefix expansion, template
  instance, unknown name, disabled unit, empty prefix, instance without
  template). Proving: systemd-run under the prefixed name and under the
  delegated names (plain and instance) refused, no side effect.
  Premise corrected: "the unit file is in the store" held only for names that
  have one.
- **I1** job mode (`flush`, `isolate`) and dependency propagation: polkit
  sees neither; documented in the caution section.
- **I2** freeze/thaw share the verbs `stop`/`start`. Measured: refused
  anyway — `systemctl freeze` asks "ref" first, and systemd's D-Bus policy
  (`org.freedesktop.systemd1.conf`) does not allow FreezeUnit/ThawUnit for
  unprivileged callers, so polkit is never asked. Proving asserts both
  refusals; docs say so. The reviewer's "granted" reading was the source
  alone, without the bus policy.
- **I3** "cannot override another rule": reworded — never denies, but its
  YES ends evaluation.
- **M1** positive control: `Finished loading` is not logged by polkit 127
  (the control failed); `Started polkitd` is, and the spike showed rule
  errors land in the same unit journal.
- **M2** aliases: docs say to list canonical ids. **M3** wording tightened.
