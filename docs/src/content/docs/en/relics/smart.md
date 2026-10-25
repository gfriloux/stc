---
title: SMART
description: Disk failure warnings from smartd, delivered by your own command.
---

**Module:** `stc.nixosModules.relics-smart`

A ZFS pool reports `DEGRADED` once a disk has already failed. SMART sees it
coming: reallocated and pending sectors, uncorrectable errors, temperature. The
relic runs smartd over every SMART-capable disk and hands each alert to a
command you provide.

No cogitator enables it. A profile cannot know whether its host has real disks,
so you turn it on where it applies:

```nix
stc.relics.smart = {
  enable = true;
  notifyCommand = ''
    ${pkgs.curl}/bin/curl -s --max-time 10 \
      -H "Title: [$STC_SMART_HOSTNAME] $STC_SMART_FAILTYPE on $STC_SMART_DEVICE" \
      -d "$STC_SMART_MESSAGE" \
      "https://ntfy.sh/$(cat ${config.sops.secrets."ntfy/topic".path})"
  '';
};
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.smart.enable` | bool | `false` | Enable the relic |
| `stc.relics.smart.autodetect` | bool | `true` | Watch every SMART-capable disk present at startup; `false` watches only `services.smartd.devices` |
| `stc.relics.smart.defaults` | string | see below | smartd.conf directives applied to every disk |
| `stc.relics.smart.hostname` | string | `networking.hostName` | Exposed as `STC_SMART_HOSTNAME` |
| `stc.relics.smart.notifyCommand` | lines | `""` | Shell snippet run for each alert. **Required**: an empty one fails the build |
| `stc.relics.smart.notifyTimeoutSec` | positive int | `60` | Seconds `notifyCommand` may run before it is killed |

The default `defaults`:

```
-a -o on -S on -s (S/../.././02|L/../../6/03) -W 4,45,55
```

| Directive | Meaning |
|---|---|
| `-a` | Every health check, attribute and error log |
| `-o on -S on` | The drive's own offline data collection and attribute autosave |
| `-s (S/../.././02\|L/../../6/03)` | Short self-test daily at 02:00, long one Saturday at 03:00 |
| `-W 4,45,55` | Report a 4 °C jump, log at 45 °C, alert at 55 °C |

Replace the whole string to change any of it. The relic adds the notification
directives itself.

## The command and its environment

The relic does not send mail, ntfy or webhooks: it runs `notifyCommand`, like
the [Docker notification relic](/stc/en/relics/docker/). The command reads its
own secrets.

| Variable | Content |
|---|---|
| `STC_SMART_DEVICE` | The disk as smartd names it: `/dev/sda [SAT]` |
| `STC_SMART_MESSAGE` | smartd's message: `Device: /dev/sda [SAT], Temperature 56 Celsius reached critical limit of 55 Celsius` |
| `STC_SMART_FAILTYPE` | `Health`, `Usage`, `SelfTest`, `ErrorCount`, `CurrentPendingSector`, `Temperature`, …, or `EmailTest` |
| `STC_SMART_HOSTNAME` | The `hostname` option |

smartd waits for the command to finish before it checks anything else, so the
relic kills it after `notifyTimeoutSec`: a stalled webhook must not stop every
SMART check. Its output (ntfy's JSON reply, an error from curl) goes to the
journal under the tag `stc-smart-notify` (`journalctl -t stc-smart-notify`).

A problem that stays (pending sectors, a disk that runs hot) is re-sent **once
a day** until it is fixed: that is smartd's `-M daily`, its default when it
keeps state, which the relic turns on (see [State](#state)). Add `-M once` or
`-M diminishing` to `defaults` for fewer reminders.

To test your command on a real host, add `-M test` at the end of `defaults`:
smartd then sends one `EmailTest` alert per disk each time it starts. The
nixpkgs option `services.smartd.notifications.test` does nothing here: nixpkgs
only adds `-M test` with its own channels.

Do not put a `-M exec` of your own in `defaults`, `services.smartd.defaults` or
a `services.smartd.devices` entry. smartd keeps only the last one, so
`notifyCommand` would never run, and the build fails to say so.

nixpkgs' own channels (`services.smartd.notifications.mail`, `wall`, `x11`)
are turned off. Each would add a second alert path to smartd.conf, and `wall`
is on by default, though nobody reads a wall on a headless server. Turning one
back on fails the build with a message saying so. To get mail, send it from
`notifyCommand`.

## Where it applies

:::caution[No SMART on virtual disks]
A virtio disk, an EBS volume or a cloud VM's disk has no SMART. smartd then
finds nothing to watch, exits, and `smartd.service` shows as **failed**. That
is on purpose: a monitor that runs while watching nothing would read as
coverage. Do not enable the relic on cloud hosts (`sarcophagus-aws`) or on VMs
without disk passthrough.
:::

It belongs on hosts with physical disks: `dreadnought`, a `sarcophagus-kvm`
host on bare metal, a workstation. It matters most on a single-disk host, where
there is no mirror to degrade and the ZFS snapshots sit on the disk that is
dying.

## State

smartd keeps per-disk state under `/var/lib/smartmontools`: attribute history,
temperature extremes, the last warning sent, the next self-test due. Without
it, every reboot re-sends the standing warnings, and with it the reminders are
daily (above). Losing it costs nothing more,
so the [state manifest](/stc/en/reference/state-manifest/) lists it as `cache`.

## Proving

`provings/smart.nix` boots a VM with an emulated SATA disk that answers SMART
(QEMU reports 31 °C) and lowers the critical temperature to 30 °C:

- smartd's own `EmailTest` and `Temperature` alerts reach `notifyCommand`, with
  the device (`/dev/sda [SAT]`), hostname and message in the environment, and
  the command's output reaches the journal;
- smartd.conf has one alert path, the relic's;
- the state file exists under `/var/lib/smartmontools`;
- a second node with only a virtio disk shows `smartd.service` failed with
  smartd's "no device" exit code, and no alert.
