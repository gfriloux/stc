---
title: Heartbeat
description: A scheduled job pings your monitor each time it succeeds, so a job that stops running raises an alert.
---

**Module:** `stc.nixosModules.relics-heartbeat`

A backup that stops running raises no alert. Every check sees a healthy host,
because nothing is broken: something simply did not happen. A dead man's
switch closes that gap. The job pings a URL **each time it succeeds**, and the
receiver ([Uptime Kuma](https://uptime.kuma.pet/) push monitor,
[healthchecks.io](https://healthchecks.io), …) alerts when the pings stop
coming.

```nix
stc.relics.heartbeat = {
  enable = true;
  units."borgbackup-job-remote".urlFile = config.sops.secrets."kuma/push-borg".path;
};
```

No cogitator enables it. You own the receiver, the URL and the alert window;
STC owns the wiring.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.heartbeat.enable` | bool | `false` | Enable the relic |
| `stc.relics.heartbeat.units.<name>.urlFile` | absolute path | — | File holding the URL to ping, read at runtime. `<name>` is the service as in `systemd.services` (no `.service`) |
| `stc.relics.heartbeat.units.<name>.packageUnit` | bool | `false` | The unit comes from `systemd.packages` (`fstrim`, …): skip the existence check, which cannot see it |
| `stc.relics.heartbeat.retries` | int | `3` | curl retries for a failed ping |
| `stc.relics.heartbeat.timeoutSec` | int | `10` | Seconds each ping attempt may take |

The build fails when a listed service:

- is not a real service (no `script`, no `ExecStart`), unless `packageUnit`
  says it comes from a package. A renamed unit therefore cannot lose its
  heartbeat silently;
- is disabled (`enable = false`);
- sets `RemainAfterExit`: it stays active after it succeeds and never
  triggers the ping.

## Only on success

A ping on "the job ran" would hide exactly the failure this exists to catch.
The relic pings only when the job **succeeded**:

| The watched service… | Ping |
|---|---|
| succeeds: exits 0, or with a status it declares in `SuccessExitStatus=` | yes |
| fails | no |
| is a oneshot stopped midway (`systemctl stop`, shutdown) | no: it ends failed |
| is a long-running service stopped midway | no, although systemd records it as a success |

The last row is why the relic does more than set systemd's `OnSuccess=`.
systemd counts a service's SIGTERM on stop as a clean end. The service then
ends with `Result=success`, and `OnSuccess=` fires. So before it pings, the
heartbeat unit checks how the job really ended: `Result=success`, and a main
process that **exited** rather than being killed.

It reads that from the snapshot systemd hands to an `OnSuccess=` unit
(`MONITOR_SERVICE_RESULT`, `MONITOR_EXIT_CODE`, `MONITOR_UNIT`), not from the
unit's current state, which a quick re-run (`Restart=`) would already have
reset. Starting `stc-heartbeat-<name>.service` by hand gives it no snapshot,
so it does not ping.

What the check cannot see is a program that catches SIGTERM and exits 0 on
its own, as many daemons with a graceful shutdown do. For systemd, that run
finished: it pings. The two "stopped midway" rows hold only for a process the
signal actually kills.

## How it runs

For each watched service `<name>`, the relic adds
`OnSuccess=stc-heartbeat-<name>.service` and that heartbeat unit. The ping
runs in its own unit, not inside the watched job:

- **A failed ping never fails the job.** If the receiver is down,
  `stc-heartbeat-<name>.service` fails on its own, and the job keeps its
  success.
- **The job's sandbox does not matter.** A job without network access
  (`PrivateNetwork=`) still gets its heartbeat.
- **The ping runs as a temporary user.** It uses `DynamicUser`, not root.

## The URL is a secret

Whoever knows the URL can feed the receiver and silence the alert. So it stays
out of the Nix store:

- It is read at runtime from `urlFile` through `LoadCredential`.
- It reaches curl on stdin (`--config -`), never on the command line, where
  any local user could read it in the process list.

## Not covered

- **Jobs inside a container.** They have no systemd unit per run. For those,
  the honest check is the result itself: the age of the latest dump file.
- **`Type=forking` services without a known main process.** systemd records
  no exit for them, so they never ping.
- **A run ending while the system shuts down.** systemd may refuse to queue
  the heartbeat then, and the ping is lost. The receiver sees one missed
  window.

## Proving

`provings/heartbeat.nix` boots a VM with a local HTTP stub standing in for the
receiver:

- a job that succeeds pings, and so does one ending with a status it declares
  in `SuccessExitStatus=`;
- starting the heartbeat unit by hand does not ping;
- a job that fails does not ping;
- a oneshot stopped midway ends failed and does not ping;
- a long-running service stopped midway ends `Result=success`, its heartbeat
  runs, and the check keeps it quiet;
- with the stub stopped, the heartbeat unit fails, and the job keeps
  `Result=success`;
- the URL is absent from the heartbeat's unit file and script.
