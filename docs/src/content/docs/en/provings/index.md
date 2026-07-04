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
