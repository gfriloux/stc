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

**What `just test` now costs.** Eight provings, **eleven VM boots** — `vm` and
`gaming` carry two nodes each, and `sarcophagus-kvm` boots its single node twice —
and the closures include KDE twice (`workstation` and `plasma`) and Steam once. On
a cold store that is a few GiB of downloads; warm, most scripts finish in 23-30 s.
`sarcophagus-kvm` is the outlier at both ends: it builds a disk image in its own
VM before the test even starts, and its script then runs 66 s for the two boots.
This is said out loud because the discipline that matters is running
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
| `sarcophagus-kvm` | `cogitator-sarcophagus-kvm` | Boots the qcow2 image the profile exists to build, twice on the same disk: the ZFS datasets the profile declares are what is actually mounted (`vmpool/root`, `vmpool/nix`, `vmpool/persist`), the relic creates the `@blank` reference the image builder does not ship, the initrd rollback runs and *succeeds*, and across a reboot a witness on the root dataset is gone while witnesses in `/persist` and under the cogitator's own `impermanence.extraDirectories` survive — with the SSH host key fingerprint unchanged, and the relic's failure reporting completely quiet on this healthy path |
| `dreadnought` | `cogitator-dreadnought` | Five relics composed on one host come up, with exactly one loaded unit failing for want of a pool; ZFS support is functional on the booted kernel; the two discriminating AWS kernel parameters reach `/proc/cmdline`; the pool-growth script carries the profile's `poolName`, `ebsDisk` and `ebsPartition`; the ZFS scrub timer carries `scrubInterval`; explicit persistence is bind-mounted, including an entry set through the cogitator's own option; the hardening suite survives the composition; the impermanence rollback ran in the initrd and failed as expected, and that failure is legible from the booted system through `stc-impermanence-state.service` rather than only from an initrd journal |

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

## Booting a real image — the external-image pattern

Seven of the eight provings let the test driver synthesise a node. `sarcophagus-kvm`
cannot: its profile's claim *is* the disk, and on a synthesised node the qemu-vm
module replaces `fileSystems` with its own set at priority 10 — so neither the
pool, nor the datasets, nor the rollback would be observable.

It follows nixpkgs' own `nixos/tests/qemu-vm-external-disk-image.nix` instead: the
node declares the image, and the driver boots *that image* rather than a root of
its own. The test script lays a copy-on-write overlay over the store path and
points `NIX_DISK_IMAGE` at it, which is also what lets the same disk carry writes
from one boot to the next.

Five node options make it work. None is a product fix — upstream exposes every one
of them for this purpose — and each was measured, not guessed:

| Option | Why |
|---|---|
| `virtualisation.directBoot.enable = false` | boot the image's own GRUB instead of the driver's kernel |
| `virtualisation.mountHostNixStore = false` | the store lives in the image |
| `virtualisation.fileSystems = lib.mkForce {}` | the documented opt-out from the `fileSystems` override. With it, `findmnt /` reports `vmpool/root` and the disk layer becomes assertable |
| `virtualisation.bootLoaderDevice = "/dev/vda"` | `qemu-vm.nix` pins `boot.loader.grub.device` to `/dev/disk/by-id/virtio-root` at priority 10, which beats the cogitator's own `mkForce`; the image builder then fails to install GRUB |
| `system.switch.enable = true` | `nixos-test-base.nix` defaults it off, and `nixos-install` inside the image builder needs `switch-to-configuration` |

The last two are failure modes you only meet by running it: both surface as an
image-build error, not as an evaluation error, and the GRUB one reports a device
that does not exist rather than a priority conflict.

This is the pattern #47 (`sarcophagus-aws`) should reuse.

## Scope limit — dreadnought cannot see the disk layer

`cogitator-dreadnought` is the profile that owns disks, and a `nixosTest` VM
replaces most of what that means. The qemu-vm module overrides whole option sets
at priority 10, which **wins** against anything a relic can write (`mkForce` is
50, a plain definition 100). On that node, measured:

| What the profile declares | What the test VM has |
|---|---|
| ZFS mounts for `/`, `/nix`, `/persist` | the VM's own `fileSystems` set |
| `boot.loader.grub.device` = the EBS disk | `/dev/disk/by-id/virtio-root` |
| the AWS relic's NTP endpoint | `timesyncd` is off in the test socle |
| the networking relic's Quad9 resolvers | no `/etc/resolv.conf` on the node at all |
| `usePredictableInterfaceNames` | `false` — the relic sets it with `mkDefault`, so it loses an ordinary priority contest rather than being forced |
| `serial-getty@ttyS0` enabled | claimed by the test instrumentation |

So pool import, dataset mounting, the boot device, the NTP endpoint, the resolvers
and the serial console are **not asserted** — for framework reasons, not code
ones. The real bench for the disk layer is the `local-vm` qcow2 image booted by
hand (`just build`, `just run`, `just ssh`), which is what proved the ZFS import
change in v0.13.0.

**The AWS serial console has no coverage at all**, and that deserves saying twice:
the getty is off here, and `console=ttyS0,115200n8` is not a usable proxy either —
measured, the test socle sets `virtualisation.qemu.consoles = ["ttyS0,115200n8"
"tty0"]` on a *bare* node, so that string is on the kernel command line whatever
the relic does. Only `nvme_core.io_timeout` and `random.trust_cpu` discriminate,
and only those two are asserted.

**Explicit persistence, on the other hand, is asserted** — it is the one disk-ish
claim that survives. `environment.persistence` does not go through `fileSystems`;
it produces systemd bind mounts, which qemu-vm leaves alone. So `/var/log`,
`/var/lib/nixos`, `/etc/machine-id` and an entry set through the cogitator's own
`impermanence.extraDirectories` option are all checked with `findmnt`. The four
`/etc/ssh/ssh_host_*` entries the relic also declares have **no mount unit at all**,
here or on a real host — and `sarcophagus-kvm` settled why, with an answer that is
not the obvious one. Upstream renders `files` through `mount-file.bash`, which
symlinks instead of bind-mounting when the target does not exist yet; that script
also runs as the `persist-files` *activation* script, which `nixos-install`
executes inside the image builder while `/persist` is still empty. The symlinks
are therefore baked into the image, which means they are inside `@blank`, which
means every rollback restores them — and `mount-file.bash` then finds a link
already pointing at its target and does nothing. sshd reads the key through it
from `/persist`. Measured either side of a rollback: the host key fingerprint does
not change.

**What the boot does establish.** The impermanence rollback service runs in the
initrd, fails for want of a pool, and the boot continues anyway — the unit is
pulled by `Wants`, not `Requires`. The booted system is therefore `degraded`, and
the proving pins the failed set to exactly one unit by filtering on systemd's
`loaded` column: `zfs-rollback` has no fragment in the booted system, so whether
its initrd failure is still listed after switch-root varies between runs, and
filtering removes that non-determinism without widening what is accepted.

Also not asserted: `services.udisks2.enable = false`, which the AWS relic sets to
keep GTK off a headless server (measured `false` on a bare node too, so it cannot
tell the relic from the default); and `stc.relics.zfs.kernel`, since pinning
`uname -r` would go red on every nixpkgs bump — measured, a node with only
`boot.supportedFilesystems = ["zfs"]` gets a working ZFS module on a newer kernel,
so loading the module proves ZFS support is functional, not that the pin is the
relic's.

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
