---
title: Overridable defaults
description: When an STC relic pins a value and when it only proposes one — the rule, what became overridable in v0.18.0, and what stays pinned on purpose.
---

Every value a relic or a cogitator writes is either a **default** you can
contradict with a plain definition, or a **pin** you cannot. Nix makes that
difference invisible until it bites: contradict a pin and the build stops with
`has conflicting definition values`, naming two files and suggesting
`lib.mkForce`, with nothing to tell you which of the two was supposed to win.

This page states which is which, and why.

## The rule

> A value is pinned when the conflict it raises is the only thing stopping an
> incoherent configuration from being built. It is a default — `lib.mkDefault` —
> whenever switching it off leaves a configuration that still makes sense.

The clearest illustration is `cogitator-dreadnought`. It enables
`stc.relics.zfs` **and** declares `fileSystems."/"` with `fsType = "zfs"`. Turn
the relic off and the configuration still evaluates: what comes out is a host
whose root is a ZFS dataset on a system with no ZFS support. It builds, and it
does not boot. The conflict is the only thing standing between you and that host,
so the relic enablement stays pinned there.

Compare `cogitator-plasma`, which also enables two relics. Plasma 6 is what the
profile *is* — decline it and the profile defines nothing, so it stays pinned.
Pipewire is an addition: decline it and you have a coherent Plasma desktop whose
audio is handled elsewhere. So it is a default, and one line expresses it:

```nix
stc.cogitator.plasma.enable = true;
stc.relics.pipewire.enable = false;   # no mkForce needed
```

## What became overridable in v0.18.0

Every entry below was pinned at normal priority before `v0.18.0` and is
`lib.mkDefault` from that release on. The effective value is unchanged, so a
configuration that does not set them builds exactly as before — verified by
identical `drvPath` on all three schematics and all eleven provings.

If you worked around one of these with `lib.mkForce`, you can drop it.

### Profiles that no longer impose their parts

| Profile | Now declinable |
|---|---|
| `cogitator-hardening` | all six sub-relics: `stc.relics.hardening.{kernel,network,filesystem,ssh,modules,scheduler}.enable` |
| `cogitator-workstation` | `stc.relics.hardening.{kernel,network,modules}.enable` |
| `cogitator-plasma` | `stc.relics.pipewire.enable` |
| `cogitator-gaming` | `stc.relics.amdGpu.enable`, `stc.relics.pipewire.enable` |
| `cogitator-docker-server` | `stc.relics.docker.socketProxy.enable`, `stc.relics.docker.crowdsec.enable`, `stc.relics.preSwitchChecks.enable` |
| `cogitator-dreadnought`, `cogitator-sarcophagus-{kvm,aws}` | `stc.relics.networking.enable`, `stc.cogitator.hardening.enable` |
| `cogitator-desktop` (Home Manager) | `stc.relics.gui.{kitty,ghostty,zen-browser}.enable` |
| `cogitator-vm` | `nix.optimise.automatic` |

The `docker-server` row is worth a sentence of its own. The Docker relics
*assert* on a missing image, so before `v0.18.0` declining CrowdSec was not
merely awkward — you had to hand CrowdSec an image you never intended to run, or
reach for `mkForce`. A gaming host on Intel or NVIDIA graphics was in the same
position with the AMD relic.

Since `v0.19.0`, the four server profiles (`docker-server`, `dreadnought`,
`sarcophagus-{kvm,aws}`) also enable two relics with `mkDefault`, both
declinable: `stc.relics.serverSurvivability.enable` and
`stc.relics.nixHousekeeping.enable`. `cogitator-vm` enables the second one too;
its `nix.optimise.automatic` row above now lives in that relic, still as a
default.

### Relic settings

| Relic | Now overridable | Why you might |
|---|---|---|
| `relics-zfs` | `boot.zfs.forceImportAll` | a non-root pool legitimately carrying a foreign hostid — **set `boot.zfs.forceImportRoot = true` as well**, or upstream asserts: *"If you enable boot.zfs.forceImportAll, you must also enable boot.zfs.forceImportRoot"* |
| `relics-boot` | `boot.loader.efi.canTouchEfiVariables` | firmware that refuses EFI variable writes; installs from a chroot. Not applicable on the two sarcophagi: as image builders they set it themselves, and there the profile has the last word |
| `relics-impermanence` | `environment.persistence.<path>.hideMounts` | seeing the bind mounts while debugging persistence |
| `relics-aws` | `services.udisks2.enable` | a host that knowingly wants it. Note the relic is no longer what blocks you — but on an image built from `nixpkgs`' own `amazon-image` module, that module writes `false` at normal priority, so a plain definition conflicts with **upstream** and you need `lib.mkForce` there |
| `relics-hardening-kernel` | `systemd.coredump.enable` | re-enabling core dumps for one debugging session — read the warning on the [hardening relics page](/stc/en/relics/hardening/) first: with the handler on, daemons dump secrets and the relic's PAM limit does **not** prevent it |
| `relics-docker-traefik` | logrotate `compress`, `delaycompress`, `missingok`, `notifempty` | your own retention policy, or a shipper that wants uncompressed files |
| `relics-yubikey-user` (Home Manager) | `programs.gpg.scdaemonSettings.{disable-ccid,pcsc-shared}` | a host running gpg without pcscd, which needs scdaemon's own CCID driver |
| `cogitator-enginseer` (Home Manager) | all of `programs.micro.settings`, `programs.direnv.silent`, `services.gpg-agent.enableSshSupport`, `catppuccin.autoEnable`, `programs.fzf.historyWidget.command` | editor taste; using gpg-agent as your SSH agent; theming tools one by one |

### Set through an STC option instead

`relics-hardening-ssh` writes the four sshd forwarding switches from its own
options, at normal priority — not as `mkDefault` values. That is tier 1 of the
rule above, and the reason is a measurement: at `mkDefault` they collided with
upstream modules writing the same setting (nixpkgs' slurm module writes
`services.openssh.settings.X11Forwarding = mkIf cfg.client.enable (mkDefault true)`),
which broke a hardened Slurm client that used to build. An option keeps STC's
value deterministic against whatever upstream defaults next release:

```nix
stc.relics.hardening.ssh = {
  allowedX11Forwarding = true;     # forward a remote GUI app
  allowedAgentForwarding = true;   # hop through a bastion with your agent
  allowedTCPForwarding = true;     # pre-existing
  allowedTunnel = true;
};
```

## What stays pinned, and why

Not a backlog. Each of these is a decision, and contradicting one should stop
your build:

- **A relic a profile's own declarations depend on** — `stc.relics.zfs` and
  `stc.relics.impermanence` in the ZFS profiles, `stc.relics.aws` in the EC2
  ones, `stc.relics.docker.traefik` in `docker-server`. The profile writes the
  filesystem layout, the boot device or the proxy wiring that assumes them.
- **The subject of the profile** — `stc.relics.plasma6` in `cogitator-plasma`.
  Declining it means wanting a different profile, not this one minus its
  subject.
- **What a relic sells** — `services.pipewire.enable` in the Pipewire relic,
  `PasswordAuthentication = false` and `PubkeyAuthentication = true` in the SSH
  hardening relic. Key-only authentication in particular: demoting it would let
  a host documented as hardened silently accept passwords again.
- **Mechanical requirements** — `boot.initrd.systemd.enable` for the
  impermanence rollback (the unit cannot exist in a scripted initrd),
  `neededForBoot` on the persist dataset.

## The seal that keeps this page true

`just option-priorities` (part of `just ci`) reads
`scripts/option-priorities.tsv` and fails on two things:

1. **An unregistered priority.** Every file under `relics/` and `cogitator/`
   that writes `lib.mkDefault`, `lib.mkForce` or `lib.mkOverride` has a row with
   the exact count and a reason. Add one without registering it and CI stops: a
   priority is a decision, and an unregistered decision is one taken in secret.
2. **A collision with an upstream default.** For every third-party option the
   register says STC writes with `mkDefault`, the locked nixpkgs and
   home-manager are searched for a module writing the same option, also with
   `mkDefault`. Two disagreeing defaults are a build error at *your* end, so
   each hit must be allow-listed with the measured reason it is harmless.

This exists because the rule above was written down and still missed something.
`v0.18.0` demoted `services.openssh.settings.X11Forwarding` to `mkDefault`;
nixpkgs' slurm module writes the same setting as
`mkIf cfg.client.enable (mkDefault true)`, and a hardened Slurm client that
built on the previous release stopped evaluating. Nothing caught it, because
nothing measured it.

The seal found a second case of the same class on its first run, older than that
chantier: `networking.useDHCP` at `mkDefault true` in the networking relic
against `networking.ifstate`'s `mkDefault false`. That is why DHCP is now
`stc.relics.networking.dhcp`, an option at normal priority.

**Known blind spot, stated rather than hidden:** the upstream search matches an
option's full dotted path and its last two components. A module that writes only
a bare leaf inside a nested block can still slip past it. Matching bare leaves
was tried and abandoned — `command`, `package` and `enable` hit half of nixpkgs,
and a check that cries wolf gets disabled.

## Checking it yourself

You do not have to take this page's word for it. Set the value you want and see
whether the configuration evaluates:

```bash
nix eval .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath
```

A pinned value fails with `has conflicting definition values` and names the file
that wrote it. A default succeeds. And to confirm a relic really went away rather
than just its option, read something only that relic writes — for the Pipewire
relic, `security.rtkit.enable`, since nixpkgs' own Plasma module enables Pipewire
on its own and its units survive the relic being declined.

The full audit, including the 93 values deliberately left pinned and the
measurements behind each verdict, is in
[issue #86](https://github.com/gfriloux/stc/issues/86) and in the repository's
`.claude/plans/v0.18.0/triage.md`.
