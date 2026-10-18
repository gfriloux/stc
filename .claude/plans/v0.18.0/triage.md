# Triage — plan: .claude/plans/v0.18.0/plan.md

Issue #86. Every definition STC writes at normal priority in `relics/` and
`cogitator/`, sorted. **141 rows** from the inventory command in the plan.

## The rule the sort converged on

The plan started from "activating is the relic's job, configuring is a
preference". Measuring broke that rule on its first real case, so the rule
below is what actually decides, and the measurement that forced it is recorded
with it.

> **A normal-priority definition is legitimate when the conflict it raises is the
> only thing stopping an incoherent configuration from evaluating. It is a defect
> when switching it off leaves a configuration that still makes sense.**

**The measurement that forced it.** `cogitator-dreadnought` turns on
`stc.relics.zfs`, and the same profile declares `fileSystems."/"` with
`fsType = "zfs"`. With `stc.relics.zfs.enable = lib.mkForce false` — which is
what a plain `= false` would do after a demotion — the configuration **still
evaluates** (`ok=true`, `drvPath` differs from baseline). What it produces is a
host whose root is a ZFS dataset on a system with no ZFS support: it builds and
does not boot. Today the normal priority turns that into
`has conflicting definition values` at build time. Demoting it would trade a
loud build error for a silent unbootable host — the first item of the plan's
*Review Focus*, met in practice on the first file examined.

So the sort is **not** "relic enablement is always a defect". It is: does the
profile also write values that assume the relic?

Derived verdicts, each recorded per row below:

- **structural** — the profile writes other values that only make sense with the
  relic on (root filesystem, boot device, persistence path). *Legitimate.*
- **additive** — switching it off leaves the profile coherent, just smaller.
  *Defect*: the consumer is entitled to compose.
- **requirement** — the relic cannot work without it (`boot.initrd.systemd` for
  the impermanence rollback, `neededForBoot` on the persist dataset).
  *Legitimate.*
- **trade** — the value *is* what the relic sells (`services.pipewire.enable` in
  the Pipewire relic, `PasswordAuthentication = false` in the SSH hardening
  relic). *Legitimate.*
- **preference** — a comfort or policy setting a consumer can reasonably want
  otherwise, and which breaks nothing when changed. *Defect.*
- **internal** — a field of a unit the relic itself creates (`serviceConfig.*`),
  not an option a consumer addresses. *Legitimate, out of criteria.*
- **false positive** — not an option definition at all. *Out of scope.*

## Measurements behind the verdicts

Run on the locked nixpkgs. Benches kept under the session scratchpad
(`nixos-probe.nix`, `hm-probe.nix`), throwaway by design.

| What | Result |
|---|---|
| Is a bare definition overridable at all? | No, 6/6 attempted overrides conflict — `programs.helix.enable`, `programs.micro.settings.mouse`, `programs.fzf.historyWidget.command`, `services.gpg-agent.enableSshSupport`, `catppuccin.autoEnable`, `catppuccin.enable`. Control: the same two with `lib.mkForce` evaluate (`ok=true`), so these are priority conflicts and not some other error. **Consequence: non-overridability is a property of the module system, not of a file — so no row needs its own measurement to establish it. Each row needs a verdict.** |
| `cogitator-plasma` without Pipewire | Evaluates, `drvPath` differs from baseline → additive |
| `cogitator-gaming` without `amdGpu` / without Pipewire | Both evaluate → additive. First attempt failed on Steam's unfree licence with no baseline to compare against — bench defect, not a product finding; `nixpkgs.config.allowUnfree` added and both remeasured |
| `cogitator-hardening` without `scheduler` / without the `ssh` relic | Both evaluate → additive |
| `cogitator-docker-server` without `crowdsec` / `socketProxy` / `preSwitchChecks` | All three evaluate → additive. Needed the proving's minimal config first (images + `acme.email` + `crowdsec.dataDir`), since the relics assert on a missing image |
| `cogitator-dreadnought` without `zfs` / `impermanence` / `aws` | All evaluate, and all leave an incoherent host → structural (see the rule above) |
| `cogitator-dreadnought` without `networking` / `hardening` | Evaluate and stay coherent → additive |
| Walking `options` to read `highestPrio` in bulk | Unusable: forcing `isDefined` on a submodule evaluates upstream defaults (`hardware.nvidia.open` → `nvidia_x11.version` on `null`), a *type* error `tryEval` does not catch |

## Defects, by file

### `cogitator/nixos/hardening.nix` — 6 defects / 6 candidates

The profile writes nothing that assumes any one of the six sub-relics; each is
independently useful. A consumer wanting the hardening suite without
`scheduler` (they manage cron themselves) or without `ssh` (they own their sshd
config) must `mkForce` today. Measured additive for two of the six.

| Line | Option | Verdict | Criterion |
|---|---|---|---|
| 30 | `stc.relics.hardening.kernel.enable` | defect — additive | 3 |
| 31 | `stc.relics.hardening.network.enable` | defect — additive | 3 |
| 32 | `stc.relics.hardening.filesystem.enable` | defect — additive | 3 |
| 33 | `stc.relics.hardening.ssh.enable` | defect — additive | 3 (measured) |
| 34 | `stc.relics.hardening.modules.enable` | defect — additive | 3 |
| 37 | `stc.relics.hardening.scheduler.enable` | defect — additive | 3 (measured) |

### `cogitator/nixos/plasma.nix` — 1 defect / 2 candidates

| Line | Option | Verdict | Criterion |
|---|---|---|---|
| 26 | `stc.relics.plasma6.enable` | **legitimate** — structural: the profile *is* Plasma 6; without the relic it defines nothing | — |
| 27 | `stc.relics.pipewire.enable` | defect — additive (measured) | 3 |

Line 27 is the third case named in the issue. Two corrections to the issue's
framing: the comment it quotes (*"already true — override only to disable"*) is
**not in the file** today, so criterion 1 does not apply; and the cogitator's doc
page lists the value as something the profile sets, not as overridable. Criterion
3 carries it alone — a Plasma host with audio handled elsewhere (JACK, bare ALSA,
or a USB interface owned by another service) is an ordinary thing to want.

### `cogitator/nixos/gaming.nix` — 2 defects / 3 candidates

| Line | Option | Verdict | Criterion |
|---|---|---|---|
| 39 | `stc.relics.amdGpu.enable` | defect — additive (measured) | 3 |
| 40 | `stc.relics.pipewire.enable` | defect — additive (measured) | 3 |
| 43 | `programs.steam.enable` | legitimate — trade | — |

`amdGpu` is the sharpest of the two: the profile is named *gaming*, not *AMD*,
and a gaming host on Intel or NVIDIA graphics has to `mkForce` the AMD relic off
today.

### `cogitator/nixos/workstation.nix` — 3 defects / 3 candidates

| Line | Option | Verdict | Criterion |
|---|---|---|---|
| 76 | `stc.relics.hardening.kernel.enable` | defect — additive | 3 |
| 77 | `stc.relics.hardening.network.enable` | defect — additive | 3 |
| 78 | `stc.relics.hardening.modules.enable` | defect — additive | 3 |

### `cogitator/nixos/dreadnought.nix` — 2 defects / 8 candidates

| Line | Option | Verdict | Criterion |
|---|---|---|---|
| 68 | `stc.relics.zfs.enable` | **legitimate** — structural (measured; this is the case that set the rule) | — |
| 69 | `stc.relics.networking.enable` | defect — additive (measured) | 3 |
| 70 | `stc.cogitator.hardening.enable` | defect — additive (measured) | 3 |
| 72 | `stc.relics.impermanence.enable` | **legitimate** — structural: the profile declares `/persist` `neededForBoot` and passes `poolName` | — |
| 77 | `stc.relics.aws.enable` | **legitimate** — structural: the profile points GRUB at `cfg.ebsDisk` and exists only for EC2 | — |
| 83 | `boot.loader.grub.enable` | legitimate — structural (the header says the profile owns the boot loader) | — |
| 90, 101 | `fileSystems."/persist".neededForBoot`, `fileSystems."/".neededForBoot` | legitimate — requirement | — |

### `cogitator/nixos/sarcophagus-aws.nix` — 2 defects / 7 candidates

| Line | Option | Verdict | Criterion |
|---|---|---|---|
| 82 | `stc.relics.zfs.enable` | legitimate — structural | — |
| 83 | `stc.relics.networking.enable` | defect — additive | 3 |
| 84 | `stc.cogitator.hardening.enable` | defect — additive | 3 |
| 86 | `stc.relics.impermanence.enable` | legitimate — structural | — |
| 91 | `stc.relics.aws.enable` | legitimate — structural | — |
| 115 | `fileSystems.<x>.neededForBoot` | legitimate — requirement | — |
| 204 | `includeChannel` | legitimate — image-build detail, see note | — |

### `cogitator/nixos/sarcophagus-kvm.nix` — 2 defects / 6 candidates

| Line | Option | Verdict | Criterion |
|---|---|---|---|
| 68 | `stc.relics.zfs.enable` | legitimate — structural | — |
| 69 | `stc.relics.networking.enable` | defect — additive | 3 |
| 70 | `stc.cogitator.hardening.enable` | defect — additive | 3 |
| 72 | `stc.relics.impermanence.enable` | legitimate — structural | — |
| 108 | `fileSystems.<x>.neededForBoot` | legitimate — requirement | — |
| 196 | `includeChannel` | legitimate — image-build detail | — |

### `cogitator/nixos/docker-server.nix` — 3 defects / 5 candidates

| Line | Option | Verdict | Criterion |
|---|---|---|---|
| 58 | `stc.relics.docker.traefik.enable` | **legitimate** — structural: the profile's whole shape is a reverse-proxied container host, and `socketProxy` is wired *inside* the Traefik relic | — |
| 61 | `stc.relics.docker.socketProxy.enable` | defect — additive (measured). The comment calls it a *"Secure default"*, which is exactly what `mkDefault` means | 1, 3 |
| 62 | `stc.relics.docker.crowdsec.enable` | defect — additive (measured) | 3 |
| 71 | `stc.relics.preSwitchChecks.enable` | defect — additive (measured) | 3 |
| 75 | `virtualisation.docker.enable` | legitimate — trade | — |

Sharpest consequence in the whole sort: because the docker relics **assert** on a
missing image, a consumer who does not want CrowdSec must still hand CrowdSec an
image today. Measured — the bare profile fails with *"stc.relics.docker.crowdsec.enable
is true but no image is set"*. They are made to configure a service they are
trying not to run.

### `cogitator/home/desktop.nix` — 3 defects / 3 candidates

| Line | Option | Verdict | Criterion |
|---|---|---|---|
| 20 | `stc.relics.gui.kitty.enable` | defect — additive | 3 |
| 21 | `stc.relics.gui.ghostty.enable` | defect — additive | 3 |
| 22 | `stc.relics.gui.zen-browser.enable` | defect — additive | 3 |

Worth noting for the backlog: issue #1 (*replace kitty → ghostty*) is a product
decision about which of the two the profile should ship. Demoting these three
does not decide it, but it does let a consumer pick today without `mkForce`.

### `cogitator/home/enginseer/default.nix` — 8 boolean defects + 3 non-boolean / 36 candidates

The twenty-odd `programs.<tool>.enable = true` lines are the profile's trade —
assembling that toolkit is what `enginseer` *is*, and a consumer who wants a
different set composes a different profile. What is **not** its trade is dictating
how each tool behaves.

| Line | Option | Verdict | Criterion |
|---|---|---|---|
| 88–92 | `programs.micro.settings.{tabstospaces,autoindent,ruler,savecursor,mouse}` | defect — preference | **1**, measured |
| 59 | `programs.direnv.silent` | defect — preference | 3 |
| 129 | `services.gpg-agent.enableSshSupport` | defect — preference | 3, measured |
| 181 | `catppuccin.autoEnable` | defect — preference | 1 |
| 27 | `programs.fzf.historyWidget.command` (non-boolean) | defect — preference | 3, measured |
| 87, 93 | `programs.micro.settings.{tabsize,"lsp.server"}` (non-boolean) | defect — preference | **1** |
| 35–37, 40, 52, 57, 58, 64, 68, 69, 72, 79–82, 85, 98, 102, 110, 120–123, 127 | `programs.*.enable`, `services.gpg-agent.enable`, integrations (`delta.enableGitIntegration`, `direnv.nix-direnv.enable`, `nix-search-tv.enableTelevisionIntegration`, `gpg-agent.enableFishIntegration`) | legitimate — trade | — |
| 53, 99, 130 | the three `enable*Integration` lines above | legitimate — trade | — |
| 178 | `catppuccin.enable` | legitimate — trade | — |

The `micro` rows are the clearest criterion-1 defect in the repository: the doc
page says, of exactly those settings, *"Override any of them from your own home
configuration."* Measured — `programs.micro.settings.mouse = false` conflicts, and
`lib.mkForce false` is required. **The documentation is false today.**

`programs.fzf.historyWidget.command` is subtler and the doc is honest about it: it
already teaches `lib.mkForce null` as the way to hand `Ctrl-R` back to fzf. The
demotion makes that `mkForce` unnecessary, so the doc has to lose it in the same
commit.

### Relic files — 8 defects

| File:line | Option | Verdict | Criterion |
|---|---|---|---|
| `relics/nixos/zfs.nix:135` | `boot.zfs.forceImportAll` | defect — preference. Its immediate neighbour `forceImportRoot` was demoted in `v0.13.0` with a long argument that applies here too; a consumer with a legitimately foreign non-root pool has the same need | 3 |
| `relics/nixos/boot.nix:19` | `boot.loader.efi.canTouchEfiVariables` | defect — preference. Setting it `false` is the standard remedy on firmware that refuses EFI variable writes, and on installs done from a chroot | 3 |
| `relics/nixos/impermanence.nix:224` | `environment.persistence.<p>.hideMounts` | defect — preference: it only changes what `mount` shows, and an operator debugging persistence wants them visible | 3 |
| `relics/nixos/aws.nix:107` | `services.udisks2.enable = false` | defect — **mis-calibrated in both directions** (measured, see below) | 3 |
| `relics/nixos/hardening/kernel.nix:88` | `systemd.coredump.enable = false` | defect — preference: disabling coredumps is sound hardening, and an operator must be able to re-enable them for one debugging session without `mkForce` | 3 |
| `relics/nixos/hardening/ssh.nix:173` | `X11Forwarding = false` | defect — preference: a workstation forwarding a remote GUI app is an ordinary need and does not weaken the relic's model for a server | 3 |
| `relics/nixos/hardening/ssh.nix:174` | `AllowAgentForwarding = false` | defect — preference: agent forwarding is how operators hop through a bastion | 3 |
| `relics/nixos/hardening/ssh.nix:176` | `PermitTunnel = false` | defect — preference | 3 |

### Relic files — legitimate, with the reason

| File:line | Option | Verdict |
|---|---|---|
| `relics/nixos/pipewire.nix:22,28,31,33,37` | `security.rtkit.enable`, `services.pipewire.{enable,alsa.enable,alsa.support32Bit,pulse.enable}` | trade — this is the relic's entire product |
| `relics/nixos/pipewire.nix:25` | `services.pulseaudio.enable = false` | trade — Pipewire's pulse layer replaces it; both on is not a configuration, it is a bug |
| `relics/nixos/plasma6.nix` (6 rows) | `displayManager.sddm.enable`, `desktopManager.plasma6.enable`, `gvfs.enable`, `tumbler.enable`, `libinput.enable`, `xdg.portal.enable` | trade |
| `relics/nixos/zfs.nix:141,146,156` | `services.zfs.autoScrub.enable`, `trim.enable`, `autoSnapshot.enable` | trade; the third is already gated by an STC option |
| `relics/nixos/impermanence.nix:150` | `boot.initrd.systemd.enable` | requirement — the rollback unit cannot exist in a scripted initrd |
| `relics/nixos/impermanence.nix:188,212` | `serviceConfig.RemainAfterExit`, `fileSystems.<persist>.neededForBoot` | internal / requirement |
| `relics/nixos/boot.nix:18` | `boot.loader.systemd-boot.enable` | trade |
| `relics/nixos/amd-gpu.nix:33,35` | `hardware.graphics.{enable,enable32Bit}` | trade |
| `relics/nixos/hardening/ssh.nix:129,140,141,142` | `services.openssh.enable`, `PasswordAuthentication`, `KbdInteractiveAuthentication`, `PubkeyAuthentication` | trade — key-only authentication is the relic's claim; demoting it would let a consumer silently re-enable passwords on a host documented as hardened |
| `relics/nixos/yubikey.nix:23` | `services.pcscd.enable` | trade |
| `relics/nixos/vaultwarden.nix:59` | `services.vaultwarden.enable` | trade |
| `relics/nixos/traefik.nix:42,48,56` | `services.traefik.enable`, two `asDefault` on the web/websecure entrypoints | trade |
| `relics/nixos/docker/socket-proxy.nix:58-62` | `CONTAINERS`, `NETWORKS`, `EVENTS`, `PING`, `VERSION` | trade — this *is* the API surface the proxy exists to narrow; `NETWORKS = false` would break the Traefik it serves |
| `relics/nixos/docker/_lib.nix:35`, `relics/nixos/aws.nix:124` | `serviceConfig.RemainAfterExit` | internal |
| `relics/home/kitty.nix:29`, `relics/home/ghostty.nix:21`, `relics/home/zen-browser.nix:20`, `relics/home/plasma-manager.nix:26` | `programs.<x>.enable` | trade — one relic per program; the consumer's switch is the relic's own `enable` |
| `cogitator/nixos/vm.nix:88,93,96,103,106` | `nix.gc.automatic` (already gated by an STC option), `programs.fish.enable`, `users.users.<u>.isNormalUser`, `services.openssh.enable`, `virtualisation.docker.enable` (gated) | trade / requirement |

### Relic files — one more defect, in a cogitator

| File:line | Option | Verdict | Criterion |
|---|---|---|---|
| `cogitator/nixos/vm.nix:85` | `nix.optimise.automatic` | defect — preference: store optimisation costs I/O on every activation and a consumer may not want it. Note: issue #59 wants this whole concern moved into a relic; demoting now does not conflict with that | 3 |

### `relics/nixos/docker/traefik.nix` — 4 defects, 3 false positives / 7 candidates

| Line | Option | Verdict |
|---|---|---|
| 329, 344, 369 | `assertion = false` inside `assertions` | **false positive** — not an option definition. The inventory's 141 therefore contains 3 rows that were never candidates |
| 430–433 | `services.logrotate.settings.traefik.{compress,delaycompress,missingok,notifempty}` | defect — preference: log rotation policy is the operator's, and these are public upstream settings |

## Summary

| Verdict | Rows |
|---|---|
| Defect | **45** boolean + 3 non-boolean |
| Legitimate (trade / structural / requirement / internal) | 93 |
| False positive | 3 |
| **Total** | **141** + 3 non-boolean named separately |

## The `udisks2` row, resolved

`relics/nixos/aws.nix:107` says `services.udisks2.enable = false`, and its comment
states the intent: *"udisks2 pulls in GTK as a dependency — not acceptable on a
headless server."*

Measured: on a bare node, `services.udisks2.enable` is **already `false`**, and
the option's own `default` is `false`. So the line changes nothing on any host
that does not ask for udisks2 — and on the one host that *does* (a consumer
composing an EC2 profile with a desktop module that turns udisks2 on), it does not
keep GTK out either: it raises `has conflicting definition values` and the build
stops. The line is mis-calibrated in both directions at once. To guarantee the
intent it would have to be `mkForce false`; to express a default it should be
`mkDefault false`.

**Ruling: `mkDefault false`, and the comment corrected to say what is true.**
`mkForce` is the wrong answer because it would silently break a consumer's desktop
rather than tell them; outright deletion is also defensible (upstream already
gives the value) but it erases a documented intent worth keeping readable. So the
line stays, demoted, and its comment says it documents an intent rather than
enforcing it — a consumer who knowingly wants udisks2 on an EC2 host gets it with
a plain definition.

## Deferred, recorded rather than fixed

- `relics/nixos/plasma6.nix` — the comment on `xdg.portal` claims *"The GTK portal
  provides a fallback for non-KDE applications"*, but `extraPortals = []` installs
  no GTK portal. The comment describes behaviour the code does not have. Out of
  this chantier's scope (not a priority question), worth an issue.
