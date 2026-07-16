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

## Adding a proving

1. Create `provings/<name>.nix` — a function `{self}: { name; nodes; testScript; }`.
   The node imports the real flake module via `self.nixosModules.cogitator-<name>`.
2. Wire it in `provings/default.nix` under `legacyPackages.provings.<name>`.
3. Add a row to the coverage table above (and its French mirror).

## Scope limit — filesystem mount hardening

The `hardening` proving does **not** assert the filesystem mount options
(`/tmp` + `/dev/shm` `noexec`, `/proc` `hidepid=2`). The relic delivers those
through `fileSystems`, but the nixosTest qemu-vm module replaces the whole
`fileSystems` set with `mkVMOverride` (priority 10), which overrides the relic's
`mkForce` (priority 50). Those mounts never exist inside the test VM, so a runtime
check would fail for framework reasons, not real ones. sysctl-based hardening is
unaffected and is asserted.

## Scope limit — docker-server asserts wiring, not running containers

The `docker-server` proving asserts the **wiring** the relics generate, not live
containers. A nixosTest VM is network-isolated, so `docker pull` cannot succeed
and the container services never come up. That is by design: STC owns the
reusable wiring, not the image lifecycle. The proving feeds placeholder images
(never pulled) and inspects the generated unit files with `systemctl cat`, which
reads them from disk regardless of runtime state; container start-up is not
awaited.
