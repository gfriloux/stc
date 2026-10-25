# Ledger — plan: .claude/plans/v0.21.0/heartbeat.md

Pre-flight: issue #102 read; `onSuccess` found in nixpkgs'
`systemd-unit-options.nix`; `OnSuccess=` semantics read in the locked
systemd's `man/systemd.unit.xml`.

Step 1: Ruling: **`OnSuccess=` plus a gate, not an `ExecStopPost=` in the
observed unit.** An ExecStopPost runs under the observed unit's user and
sandbox (a `PrivateNetwork=` job could not ping), delays its stop by the
curl, and its failure marks the unit failed unless prefixed. A separate unit
keeps the ping's failure visible on its own and out of the observed unit's
result. The gate in the heartbeat unit is what `OnSuccess=` lacks.

Step 1: Ruling: **one heartbeat unit per observed unit, not a template.** A
template would need a runtime lookup from the instance name to the URL file;
one unit each carries its own `LoadCredential`.

Step 2: `relics/nixos/heartbeat.nix`, registered as `relics-heartbeat`.

Step 3: `provings/heartbeat.nix` (registry, `test` recipe). Python stub on
127.0.0.1:8000 records paths. Three runs to green:
- run 1 timed out in the "stopped midway" case: the wait used
  `systemctl is-active … | grep`, and `is-active` exits 3 on `activating`, so
  the pipe never passed; the oneshot ran its 300 s and pinged legitimately.
- run 2: with the wait fixed, the stopped oneshot ended `code=killed,
  status=15/TERM`, "Failed with result 'signal'" — failed, so `OnSuccess=`
  never fired and the gate was never reached. **The plan's premise was wrong
  for oneshots.**
- run 3: added `stc-hb-daemon` (`Type=simple`, `sleep 300`). Stopped midway it
  ends `Result=success`, `OnSuccess=` fires, the heartbeat logs "did not
  succeed", no ping. That is the case the gate exists for, now measured.
Final: success pings; failure, stopped oneshot and stopped service do not; a
stopped stub fails the heartbeat unit while the watched job keeps
`Result=success`; "SECRET" absent from the heartbeat unit file and script.

Step 4: `relics/heartbeat.md` EN + FR (success table, why a gate on top of
OnSuccess=, own unit, URL secrecy, out of scope, proving); relics index row
and link; provings index fourteen provings, twenty boots, coverage row.

Step 2 (eval): an unknown unit and a RemainAfterExit service fail their
assertions; a real `services.borgbackup.jobs.remote` watched as
`borgbackup-job-remote` evaluates clean.

Closing review (fresh context): no Critical. Important, all taken:
- I1 the `ExecMainStatus = 0` check refused successes the unit declares
  (`SuccessExitStatus=`; nixpkgs' tsm-client sets "4 8"). Dropped: with
  `Result=success` an exited process already means 0 or a declared status.
  Proving: `stc-hb-declared` (`exit 3`, `SuccessExitStatus=3`) pings.
- I2 docs overclaimed the "stopped midway" rows: a program that catches
  SIGTERM and exits 0 is, for systemd, a finished run, and pings. Stated in
  the module header and both docs.
- I3 race with a quick re-run (`Restart=`): `systemctl show` reads live
  values the next run resets. The gate now reads `MONITOR_SERVICE_RESULT`,
  `MONITOR_EXIT_CODE` and `MONITOR_UNIT` (systemd's snapshot for OnSuccess=
  units, `src/core/service.c`, `man/systemd.exec.xml`), atomic and without
  D-Bus. Side effect, proven: a manual start has no snapshot and does not
  ping.
- I4 package-provided units (fstrim) were refused: new per-unit
  `packageUnit = true` skips the existence check.
Minor taken: `RemainAfterExit` normalised over bool and "yes"/"true"/"on"/"1";
assertion on `enable = false`; unit-name validation; URL file first line
only, CR stripped, `\` and `"` escaped for curl's config syntax; docs name
`Type=forking` without a main PID and a run ending during shutdown (an
OnSuccess= job refused, ping lost) as not covered.
Minor not taken: an argv check in the proving (curl's argv carries no URL by
construction: `printf` is a builtin, the URL goes through a pipe); composing
with the hardening relic (no longer reads D-Bus, so hidepid is moot).
