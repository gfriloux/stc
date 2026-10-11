---
title: Pre-Switch Checks
description: Refuse to activate another host's closure, and show the diff on a remote deploy.
---

**Module:** `stc.nixosModules.relics-pre-switch-checks`

`system.preSwitchChecks` runs shell checks on the **target machine** after the
closure has been copied but **before** it is activated. A check that exits
non-zero aborts the switch with the old system still running.

This relic puts two checks there. Both address failure modes a consumer cannot
guard against on their own.

## 1. Deploying the wrong host's closure

A multi-host consumer deploys with near-identical commands:

```bash
nixos-rebuild switch --flake .#clochette   --target-host you@clochette.example
nixos-rebuild switch --flake .#RogueLeader --target-host you@rogueleader.home
```

Swap the flake attribute or the target and host A's closure activates on host B.
Nothing stops it. On a Docker server the result is immediate and ugly: wrong
containers, wrong Traefik routers, wrong users, wrong secrets — and if the change
touches SSH or sudo, possibly no way back in.

## 2. No diff on a remote deploy

Locally, `nh os switch` shows what changed. `nixos-rebuild --target-host` shows
nothing: the operator activates a closure on a production host without seeing
which packages moved.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.preSwitchChecks.enable` | bool | `false` | Enable the checks |
| `stc.relics.preSwitchChecks.hostnameGuard` | bool | `true` | Abort unless the closure belongs to the running host |
| `stc.relics.preSwitchChecks.closureDiff` | bool | `true` | Print a `dix` diff before activating |

`cogitator-docker-server` enables this relic with both checks on. Any other
profile, including `dreadnought`, is one line away:

```nix
stc.relics.preSwitchChecks.enable = true;
```

:::caution[This can abort a deploy that used to work]
The guard compares the hostname the machine is actually running against the one
the incoming closure was built for. If those differ on your hosts today — a name
overwritten by DHCP or `cloud-init`, a config whose `networking.hostName` was
never corrected — your next `nixos-rebuild` aborts.

Your build does not break. Only the activation stops, and the old system keeps
running. Three ways out, in order of preference:

1. fix the mismatch — it is telling you something true;
2. `stc.relics.preSwitchChecks.hostnameGuard = false;` if you do not want the
   guard;
3. `NIXOS_NO_CHECK=1 nixos-rebuild switch …` for a single deploy.
:::

## When the Guard Fires

| Situation | Guard | Why |
|-----------|-------|-----|
| action `switch`, `test`, `check` | runs | All three touch the running system |
| action `boot` | **runs** | Deliberately unlike upstream's switch inhibitors, which skip it: writing the wrong host's bootloader entry is precisely the disaster, and it only surfaces at the next reboot |
| action `dry-activate` | skipped | Nothing is activated, so aborting would prevent no damage |
| `/run/booted-system` absent | skipped | An install is in progress — see below |
| `networking.hostName` empty | skipped | A host named by DHCP has no expected name to compare against |

The expected name is baked in at evaluation time from `networking.hostName`. That
is not circular: the check travels *inside* the incoming closure, so by
construction that value is the name of the host this closure was built for.

Comparison is on the **short name**, the part before the first dot on both sides,
because systemd may have set the FQDN when `networking.domain` is defined and a
strict comparison would abort a correct deploy. The trade-off is explicit: two
hosts whose short names match but whose domains differ are not distinguished.

### Why the install case matters

`nixos-install` — and therefore `nixos-anywhere`, which is how STC's
[schematics](/stc/en/schematics/) are installed — activates the new system inside
a `nixos-enter` chroot. That chroot bind-mounts only `/dev`, `/sys` and `/proc`,
so `/run` belongs to the freshly installed target and is empty, while
`/proc/sys/kernel/hostname` is still the **installer's**. Without the
`/run/booted-system` test, the guard would abort every fresh install. It is
load-bearing, not defensive.

## The Only Escape Hatch Is `NIXOS_NO_CHECK=1`

That is a measured fact, not a preference. srvos offers an `EXPECTED_HOSTNAME`
variable for this; it cannot reach the check when you deploy with
`nixos-rebuild`:

- `nixos-rebuild-ng` runs `switch-to-configuration` under `/usr/bin/env -i` with
  a **closed allowlist** of three variables — `LOCALE_ARCHIVE`,
  `NIXOS_NO_CHECK`, `NIXOS_INSTALL_BOOTLOADER`;
- it wraps that in `systemd-run -E` for the same three;
- and only `NIXOS_NO_CHECK` is in sudo's `env_keep`.

A variable of ours would reach nothing, so there is none.

:::note[What the hatch costs]
`NIXOS_NO_CHECK=1` disables **all** pre-switch checks, including upstream's own
switch inhibitors. It is the price of an escape hatch that demonstrably works
rather than one that silently does not.
:::

## There Is No Prompt

srvos asks for confirmation on stdin. Under `nixos-rebuild --target-host` the
script runs through SSH beneath `systemd-run --pipe`, where stdin is not a
reliable terminal — and under the `set -euo pipefail` that
`pkgs.writeShellApplication` imposes, a `read` from an empty stdin returns
non-zero and aborts the switch anyway.

Prompting is therefore a non-deterministic way of spelling *abort*. The guard
aborts, and its message names both ways forward.

## The Closure Diff

Informational, and it can never fail a switch: `dix` is called with a trailing
`||`, so a diff tool that errors prints a warning and the fragment still exits 0.
That is verified behaviourally in `provings/docker-server.nix`, by handing the
script a closure path that does not exist and asserting it still succeeds.

It adds `dix` (~4 MiB unpacked, in the binary cache) to the closure of every host
that enables it. That is why it is a separate toggle: turn it off and keep the
guard.

To use `nvd` instead — the two have different command lines, so a package option
here would be a trap:

```nix
stc.relics.preSwitchChecks.closureDiff = false;

system.preSwitchChecks.myDiff = ''
  ${pkgs.nvd}/bin/nvd diff /run/current-system "$1"
'';
```

## Writing Your Own Check

Fragment names are not cosmetic: upstream renders them with
`lib.mapAttrsToList`, so they run in **attribute-name order**. This relic's guard
is called `stcAbortWrongHost` so it sorts before `stcClosureDiff` — otherwise a
wrong-host deploy prints a diff of two unrelated closures first and scrolls the
abort message out of view. Keep that in mind when naming yours.

Each fragment receives the incoming closure as `$1` and the action verb as `$2`,
is wrapped in `( set -e … ) >&2` (so stdout is already stderr — no redirection
needed), and is concatenated with the others into a single
`pkgs.writeShellApplication`. That last point has teeth: **shellcheck runs at
build time**, so an unquoted expansion or an unused variable breaks the system
build, not just a deploy.

## See Also

- [Relics overview](/stc/en/relics/) — all relics
- [Docker Server profile](/stc/en/cogitator/docker-server/) — enables this relic
- [VM Variant](/stc/en/relics/vm-variant/) — the other half of the gate: boot the host before deploying it
