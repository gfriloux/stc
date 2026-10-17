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

## Adding a proving

1. Create `provings/<name>.nix` — a function `{self}: { name; nodes; testScript; }`.
   The node imports the real flake module via `self.nixosModules.cogitator-<name>`.
2. Wire it in `provings/default.nix` under `legacyPackages.provings.<name>`.
3. **Add it to the `test` recipe in the `Justfile`.** A proving registered in
   `provings/default.nix` but absent from the recipe never runs, and a green
   `just test` is then a false green — this step is not optional.
4. Add a row to the coverage table above (and its French mirror).

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
