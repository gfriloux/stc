---
title: Provings
description: Internal nixosTests that boot a VM and assert a cogitator behaves as claimed.
sidebar:
  order: 0
---

A **proving** is a behaviour test: a `nixosTest` that boots a VM with a cogitator
enabled and asserts it actually does what it claims — sysctls in effect, services
configured as intended, and so on. Where `nix flake check` and the Purity Seals
prove a flake *evaluates*, the provings prove a system *works*. This is the Rite
of Proving of the machine spirit.

Provings are **internal QA for STC itself**. They are not a consumer-facing API —
consumers never import them.

## Out of the gate, on purpose

Provings are exposed under `legacyPackages.<system>.provings.*`, an output tree
that `nix flake check` **deliberately skips**. They are therefore **not part of
the `just ci` gate**: a VM test is heavy, and the CI gate stays fast and static.

- Run them by hand: `just test` (each proving builds and runs its VM).
- Linux only (`x86_64-linux` / `aarch64-linux`) — the attribute is empty elsewhere.
- Builder: `pkgs.testers.runNixOSTest`.

**What `just test` now costs.** Seven provings, **nine VM boots** — `vm` and
`gaming` carry two nodes each — and the closures include KDE twice (`workstation`
and `plasma`) and Steam once. On a cold store that is a few GiB of downloads; warm,
the whole suite runs in a couple of minutes of VM time (each script finishes in
23-30 s). This is said out loud because the discipline that matters is running
`just test` before closing a branch that touched a cogitator: a recipe too heavy
to run is a gate that quietly stops being one. Build a single proving while
iterating — `nix build .#legacyPackages.x86_64-linux.provings.<name> -L` — and run
the full recipe before the branch closes.

Not to be confused with `forge/purity-seals/`, which produces reusable *check
builders* for **consumer** flakes. Provings test STC; they are not exported.

## Running a proving

```bash
just test
# or, directly:
nix build .#legacyPackages.x86_64-linux.provings.hardening -L --no-write-lock-file
```

## Coverage

| Proving | Cogitator under test | What it asserts |
|---------|----------------------|-----------------|
| `hardening` | `cogitator-hardening` | Kernel and network sysctl hardening are live; SSH is key-only with root login refused |
| `docker-server` | `cogitator-docker-server` | Container units carry their pinned image and healthcheck flags; docker networks, the notify `OnFailure` hook and health-watch timers are wired; the Traefik static config renders with the CrowdSec bouncer plugin and socket-proxy endpoint |
| `workstation` | `cogitator-workstation` | The profile wires its three concerns: the hardening socle (kernel/network sysctl, module blacklist) is live, YubiKey `pcscd` is present, and the desktop's display-manager unit exists |
| `vm` | `cogitator-vm` | The primary user is in `wheel` with a working fish login shell and lingering enabled; a key declared through `authorizedKeys` actually authenticates over SSH, not merely that port 22 answers; the GC timer fires weekly and its script carries the declared retention; Docker is absent by default and, on a second node, the opt-in path wires both the daemon and the `docker` group |
| `plasma` | `cogitator-plasma` | SDDM is the display manager and runs Wayland with the Plasma session as its default; the session file exists in the directory sddm actually points at; both relic tunables (`keyboardLayout`, `sddmTheme`) reach the rendered configuration; the XDG portal carries the wildcard the relic configures; rtkit, the 32-bit ALSA bridge and the `default.target` want that starts WirePlumber with the graphical session are all in place; gvfs and tumbler are reachable by the session |
| `gaming` | `cogitator-gaming` | Steam is wired, with the udev rules that make a controller usable without root; the AMD relic's VDPAU/VAAPI driver reaches the merged driver tree; the Pipewire relic's three claims (rtkit, the 32-bit ALSA bridge, PulseAudio compat) are in place; Steam Remote Play is closed by default and, on a second node, opens both its UDP range and its TCP ports |
| `dreadnought` | `cogitator-dreadnought` | Five relics composed on one host come up, with only the pool-dependent units failing; the pinned ZFS kernel boots and its module loads; the AWS kernel parameters reach `/proc/cmdline`; the pool-growth and trim units are installed; the hardening suite survives the composition; the impermanence rollback ran in the initrd |

## Adding a proving

1. Create `provings/<name>.nix` — a function `{self}: { name; nodes; testScript; }`.
   The node imports the real flake module via `self.nixosModules.cogitator-<name>`.
2. Wire it in `provings/default.nix` under `legacyPackages.provings.<name>`.
3. **Add it to the `test` recipe in the `Justfile`.** A proving registered in
   `provings/default.nix` but absent from the recipe never runs, and a green
   `just test` is then a false green — this step is not optional.
4. Add a row to the coverage table above (and its French mirror).

## Unfree packages in a proving

`cogitator-gaming` enables `programs.steam`, and Steam is unfree. The `pkgs` that
flake-parts hands the registry does not allow unfree packages, so that proving
cannot be built from it — and neither way of relaxing it from inside the test
works. Both are measured closed:

| Attempt | Result |
|---|---|
| `nixpkgs.config.allowUnfree = true` in the node | `error: nixpkgs.config is set to read-only` |
| `node.pkgs = <instance>` | `error: node.pkgs is defined multiple times` — `runNixOSTest` defines it itself |

So the instance has to be the one *building* the test:

```nix
pkgs-unfree = import inputs.nixpkgs {
  inherit system;
  config.allowUnfree = true;
};
# …
gaming = pkgs-unfree.testers.runNixOSTest (import ./gaming.nix {inherit self;});
```

It is scoped to that single registry line, the same way `forge/default.nix` scopes
one for Terraform's BSL licence. The five other provings keep a byte-identical
`drvPath` with the instance present, which is how that was checked rather than
assumed — though that check is close to a formality, since `pkgs-unfree` is a lazy
binding Nix never forces for them.

**What the scoping does and does not buy.** No other flake output can pull an
unfree package through this. But inside that one proving, the node's *entire*
closure is evaluated with `allowUnfree = true` — so if a relic composed into
`cogitator-gaming` later pulls in unfree firmware or a proprietary driver, that
proving accepts it silently where every other proving would fail the evaluation.
The instance buys per-output scoping, not per-package scoping.

## Scope limit — dreadnought cannot see the disk layer

`cogitator-dreadnought` is the profile that owns disks, and a `nixosTest` VM
replaces most of what that means. The qemu-vm module overrides whole option sets
at priority 10 — below even `mkForce` at 50 — so on that node, measured:

| What the profile declares | What the test VM has |
|---|---|
| ZFS mounts for `/`, `/nix`, `/persist` | the VM's own `fileSystems` set |
| `boot.loader.grub.device` = the EBS disk | `/dev/disk/by-id/virtio-root` |
| `networking.timeServers` = the AWS NTP endpoint | `timesyncd` is off in the test socle |
| `usePredictableInterfaceNames` | forced back to `false` |
| `serial-getty@ttyS0` enabled | claimed by the test instrumentation |

So pool import, dataset mounting, the boot device, the NTP endpoint and the
serial console are **not asserted** — for framework reasons, not code ones. The
real bench for the disk layer is the `local-vm` qcow2 image booted by hand
(`just build`, `just run`, `just ssh`), which is what proved the ZFS import change
in v0.13.0.

**What the boot does establish.** The impermanence relic's rollback service runs
in the initrd, fails for want of a pool, and the boot continues anyway — the unit
is pulled by `Wants`, not `Requires`. The booted system is therefore `degraded`,
and the proving asserts the failed set is bounded to the two pool-dependent units
rather than tolerating failures silently. `zfs-rollback.service` ran in the
initrd, and whether its failure is still listed after switch-root was observed
both ways across runs, so the assertion bounds the set instead of pinning it —
pinning would be flaky for a systemd-internal reason.

Also not asserted: `services.udisks2.enable = false`, which the AWS relic sets to
keep GTK off a headless server. Measured `false` on a bare `nixosTest` node too,
so the assertion could not tell the relic from the default.

## Scope limit — filesystem mount hardening

The `hardening` proving does **not** assert the filesystem mount options
(`/tmp` + `/dev/shm` `noexec`, `/proc` `hidepid=2`). The relic delivers those
through `fileSystems`, but the nixosTest qemu-vm module replaces the whole
`fileSystems` set with `mkVMOverride` (priority 10), which overrides the relic's
`mkForce` (priority 50). Those mounts never exist inside the test VM, so a runtime
check would fail for framework reasons, not real ones. sysctl-based hardening is
unaffected and is asserted.

## Scope limit — plasma asserts configuration, not a graphical session

The `plasma` proving waits for `multi-user.target` and reads the rendered
configuration and unit files from disk. It does not bring up a Plasma session:
that is heavy in a VM, and the session itself is upstream's, not STC's.

**What it deliberately does not assert, and why.** Every candidate assertion was
measured three ways — on a bare `nixosTest` node, on a node carrying nixpkgs'
`plasma6` module without STC, and on the STC node — so that each one can tell the
relic apart from a default. Four candidates failed that test and were dropped:

- `services.pulseaudio.enable` and `services.xserver.enable` are already `false`
  with none of these relics imported, so "PulseAudio is off" and "no X server"
  would hold whatever STC did.
- `services.pipewire.enable` and `xdg.portal.enable` are set by nixpkgs' own
  `plasma6` module, so the Pipewire and portal **user units** exist even with
  STC's Pipewire relic removed from the cogitator. The proving asserts what does
  discriminate instead: `rtkit`, the `libs.32Bit` line in
  `/etc/alsa/conf.d/49-pipewire-modules.conf`, and the `default.target` want on
  WirePlumber.

An assertion that cannot distinguish the relic from the default proves nothing
and reads as coverage, which is worse than an admitted gap.

## Scope limit — docker-server asserts wiring, not running containers

The `docker-server` proving asserts the **wiring** the relics generate, not live
containers. A nixosTest VM is network-isolated, so `docker pull` cannot succeed
and the container services never come up. That is by design: STC owns the
reusable wiring, not the image lifecycle. The proving feeds placeholder images
(never pulled) and inspects the generated unit files with `systemctl cat`, which
reads them from disk regardless of runtime state; container start-up is not
awaited.
