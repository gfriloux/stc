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

**What `just test` now costs.** Fourteen provings, **twenty VM boots** — `vm`,
`gaming`, `home-desktop`, `docker-server` and `smart` each boot two nodes, `dreadnought` declares a second
node it never starts, `docker-server` a third, and `sarcophagus-kvm` boots its single node twice — and the closures include KDE twice (`workstation` and
`plasma`), Steam once, the enginseer toolkit's 31 named packages, and GIMP, VLC
and Zen Browser for the desktop profile. On a cold store that is a few GiB of
downloads; warm, most scripts finish in 23-30 s, `enginseer` in 25 s. The two
sarcophagi are the outliers, because each **builds a disk image in its own VM
before its test even starts**: `sarcophagus-kvm` then runs 66 s for its two
boots, and `sarcophagus-aws` 32 s for its one.
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
| `docker-server` | `cogitator-docker-server` | Container units carry their pinned image and healthcheck flags; docker networks, the notify `OnFailure` hook and health-watch timers are wired; the Traefik static config renders with the CrowdSec bouncer plugin and socket-proxy endpoint; the docker guards warn about exactly the unlabelled public port and raw socket mount — not a labelled container, not STC's own Traefik 80/443 and proxy, not a loopback bind, but a port appended to Traefik; nothing on a node that declines them; and, read from a third node that never boots, Traefik's raw-socket fallback and a stand-in named like the proxy once the proxy relic is off |
| `workstation` | `cogitator-workstation` | The profile wires its three concerns: the hardening socle (kernel/network sysctl, module blacklist) is live, YubiKey `pcscd` is present, and the desktop's display-manager unit exists |
| `vm` | `cogitator-vm` | The primary user is in `wheel` with a working fish login shell and lingering enabled; a key declared through `authorizedKeys` actually authenticates over SSH, not merely that port 22 answers; the GC timer fires weekly and its script carries the declared retention; Docker is absent by default and, on a second node, the opt-in path wires both the daemon and the `docker` group |
| `plasma` | `cogitator-plasma` | SDDM is the display manager and runs Wayland with the Plasma session as its default; the session file exists in the directory sddm actually points at; both relic tunables (`keyboardLayout`, `sddmTheme`) reach the rendered configuration; the XDG portal carries the wildcard the relic configures; rtkit, the 32-bit ALSA bridge and the `default.target` want that starts WirePlumber with the graphical session are all in place; gvfs and tumbler are reachable by the session |
| `gaming` | `cogitator-gaming` | Steam is wired, with the udev rules that make a controller usable without root; the AMD relic's VDPAU/VAAPI driver reaches the merged driver tree; the Pipewire relic's three claims (rtkit, the 32-bit ALSA bridge, PulseAudio compat) are in place; Steam Remote Play is closed by default and, on a second node, opens both its UDP range and its TCP ports |
| `sarcophagus-kvm` | `cogitator-sarcophagus-kvm` | Boots the qcow2 image the profile exists to build, twice on the same disk: the ZFS datasets the profile declares are what is actually mounted (`vmpool/root`, `vmpool/nix`, `vmpool/persist`), the relic creates the `@blank` reference the image builder does not ship, the initrd rollback runs and *succeeds*, and across a reboot a witness on the root dataset is gone while witnesses in `/persist` and under the cogitator's own `impermanence.extraDirectories` survive — with the SSH host key fingerprint unchanged, and the relic's failure reporting completely quiet on this healthy path |
| `sarcophagus-aws` | `cogitator-sarcophagus-aws` | Boots the raw AMI image the profile exists to build, on a disk **larger than the image**: the ZFS pool actually grows to fill the volume under it (`stc-grow-pool` completes *and* `zpool list` clears the image's own size), the profile's datasets are what is mounted, `/boot` is a plain FAT ESP whose label resolves to the mounted device, the two discriminating AWS kernel parameters are live, `xen_fbfront` is blacklisted, the EC2 udev rules are installed, and both instance classes' network drivers are requested — with the Xen one failing to insert on this bench *without failing the boot*, which is what lets one image serve Nitro and Xen |
| `enginseer` | `cogitator-enginseer` (Home Manager) | Activates the profile for a test user inside a VM and asserts its runtime claims: the three aliases it declares resolve in a shell that really started (not the six `programs.lsd` also renders), `oh-my-posh` initialises from the theme the cogitator ships, `git` itself selects `delta` as its diff pager with delta's `interactive.diffFilter` in place, direnv is hooked into fish with nix-direnv and silenced, `FZF_CTRL_R_COMMAND` is set and empty so Ctrl-R belongs to atuin, `~/.ssh/config` carries multiplexing *without* Home Manager's legacy default block, gpg-agent's `pinentry-program` is the headless `pinentry-curses`, and the declared catppuccin flavour reaches bat's theme |
| `home-desktop` | `cogitator-desktop` (Home Manager) | Two nodes. On the profile **alone**: kitty renders its configuration, the ghostty relic renders its user unit and overrides, zen-browser reaches the user profile as `zen-beta`, the cogitator's own `gimp` and `vlc` are installed, and the kitty relic's `fonts` option makes the nerd fonts visible to `fc-list`. On a node carrying **both** Home Manager profiles: desktop's `mkForce pinentry-qt` wins the contest against enginseer's `mkDefault pinentry-curses` — the only cross-cogitator interaction proven in this suite — and one claim from each profile still holds under composition |
| `dreadnought` | `cogitator-dreadnought` | Five relics composed on one host come up, with exactly one loaded unit failing for want of a pool; ZFS support is functional on the booted kernel; the two discriminating AWS kernel parameters reach `/proc/cmdline`; the pool-growth script carries the profile's `poolName`, `ebsDisk` and `ebsPartition`; the ZFS scrub timer carries `scrubInterval`; explicit persistence is bind-mounted, including an entry set through the cogitator's own option; the hardening suite survives the composition; the impermanence rollback ran in the initrd and failed as expected, and that failure is legible from the booted system through `stc-impermanence-state.service` rather than only from an initrd journal |
| `smart` | `relics-smart` (no cogitator enables it) | On an emulated SATA disk that answers SMART, smartd's own `EmailTest` and `Temperature` alerts reach `notifyCommand` with the documented environment, and its output reaches the journal; smartd.conf carries one alert path; the state file exists. A second node with only a virtio disk shows `smartd.service` failed with smartd's "no device" exit, and no alert |
| `polkit-units` | `relics-polkit-units` (no cogitator enables it) | Unprivileged users run `systemctl`: a group member restarts, stops and starts the named unit and restarts one covered only by the prefix, and drives a listed template instance; another instance, another unit, another verb, freeze/thaw, `enable`, a non-member, a manager-level call with no unit and `systemd-run --unit=` under a prefixed or delegated name are all refused, with no rule error in polkit's log. Run twice, the second time with `/proc` remounted `hidepid=2` as the hardening relic sets it |
| `heartbeat` | `relics-heartbeat` (no cogitator enables it) | Against a local HTTP stub: a successful job pings, and so does one ending with a status it declares in `SuccessExitStatus=`; a manual start of the heartbeat does not; a failed job, a oneshot stopped midway and a long-running service stopped midway (which systemd records as `Result=success`) do not; an unreachable receiver fails only the heartbeat unit; the URL appears in no unit file or script |

## Adding a proving

1. Create `provings/<name>.nix` — a function `{self}: { name; nodes; testScript; }`.
   The node imports the real flake module via `self.nixosModules.cogitator-<name>`.
   A Home Manager cogitator takes `{self, inputs}` instead, because its node has
   to import Home Manager's NixOS module out of an input — see *Proving a Home
   Manager cogitator* below. The two signatures coexist on purpose.
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
one for Terraform's BSL licence. The other provings keep a byte-identical
`drvPath` with the instance present, which is how that was checked rather than
assumed — though that check is close to a formality, since `pkgs-unfree` is a lazy
binding Nix never forces for them.

**What the scoping does and does not buy.** No other flake output can pull an
unfree package through this. But inside that one proving, the node's *entire*
closure is evaluated with `allowUnfree = true` — so if a relic composed into
`cogitator-gaming` later pulls in unfree firmware or a proprietary driver, that
proving accepts it silently where every other proving would fail the evaluation.
The instance buys per-output scoping, not per-package scoping.

## Proving a Home Manager cogitator

`cogitator-enginseer` is a Home Manager profile, not a NixOS one, and
[#50](https://github.com/gfriloux/stc/issues/50) deliberately left the mechanism
open — *"doesn't need to be `runNixOSTest` if that's the wrong tool for a HM-only
module"*. It is the right tool, and the reason is worth stating because the
cheaper option is tempting.

**Why not build `home.activationPackage`?** Because that proves the configuration
*evaluates and builds*, which `nix flake check` and the Purity Seals already
prove. A proving that reduced to a `nix build` would add nothing to the gate while
carrying the name of a proving. And enginseer's claims are runtime claims: an
alias that resolves in a shell that actually started, `delta` being the pager
`git` itself selects, the session variable that hands Ctrl-R to atuin. None of
that is visible in a `drvPath`.

So the node imports `inputs.home-manager.nixosModules.home-manager` and attaches
the cogitator to a test user through `home-manager.users.<u>.imports`. Activation
then becomes an ordinary systemd unit of the node — measured,
`home-manager-<u>.service` — and `wait_for_unit` applies like anywhere else. This
is also why the two Home Manager provings take `inputs` where the other nine take
only `self`: `self.homeModules.*` alone cannot attach a home configuration to a
node.

**Four bench concessions**, in the same spirit as the external-image pattern's
five. None is a recommendation for how to wire a consumer:

| Option | Why |
|---|---|
| `users.users.<u>.shell = pkgs.fish` | Home Manager does not set the login shell — measured. Without it there is no fish to start, so the login-shell half of the profile could not be observed. On the `enginseer` node and on `home-desktop`'s composed node only: the desktop-alone node sets no shell, because that profile claims none |
| `programs.fish.enable = true` | Forced by an upstream assertion once a user's login shell is fish: otherwise fish "[lacks] the basic nix directories in its PATH and might make logging in as that user impossible". Satisfied rather than suppressed with `ignoreShellProgramCheck`, because those nodes do log in. Paired with the row above, so it too is absent from the desktop-alone node |
| `home-manager.useGlobalPkgs = true` | HM uses the node's `pkgs` instead of importing its own nixpkgs. Keeps one instance at evaluation — and keeps the unfree note above true for Home Manager provings too, which a second instance would quietly falsify |
| `home-manager.useUserPackages = true` | Packages land in `users.users.<u>.packages`, hence under `/etc/profiles/per-user/<u>`, a deterministic path — which is what makes the zen-browser assertion writable in `home-desktop`, that relic rendering no file of its own. Measured, and narrower than it looks: `useUserPackages` moves the activation `drvPath`, while `useGlobalPkgs` alone is byte-identical to the default — so only the first is a closure change, and the second earns its place by removing a second nixpkgs instance |

Measured and worth saying: **neither Home Manager cogitator needs the unfree
instance.** `gaming` remains the only unfree proving in the suite.

### What measuring first disqualified

The reference node here is one carrying Home Manager and the test user but **no
STC cogitator**. On it, HM renders exactly five files
(`environment.d/10-home-manager.conf`, three `fontconfig/conf.d/*`,
`systemd/user/tray.target`) plus two `.keep` stubs, and both
`programs.fish.enable` and `services.gpg-agent.enable` are `false`. Five
candidate assertions were corrected or dropped against it, each of which would
otherwise have proved nothing:

- **Six of the nine fish aliases are not STC's.** `ls`, `ll`, `la`, `lt`,
  `lla` and `llt` come from Home Manager's `programs.lsd` module — and worse,
  NixOS' `environment.shellAliases` *itself* defaults to `{l, ll, ls}`, so
  asserting `ll` would have been green with no cogitator at all. Only
  `cat → bat`, `cp → xcp` and `ping → prettyping` come from this profile.
- **`delta` is not wired through `core.pager`.** The integration is
  `[pager] diff/log/show/blame` plus `interactive.diffFilter` — `[delta]` itself
  carries only `features`. `core.pager` is unset, so a check on it would not
  have been a false green but a hard red: `git config --get` exits 1.
- **`programs.direnv.silent` writes no "silent" anywhere.** It renders a
  `[global]` section with `log_filter = "^$"`.
- **`programs.fzf.historyWidget.command = ""` does not change `config.fish`.**
  Measured against the counterfactual, the only difference between the two
  rendered files is a store path: the setting travels through
  `hm-session-vars.fish` as `FZF_CTRL_R_COMMAND`. Measured both ways: the
  cogitator renders it **set and empty**, and the option's own default (`null`)
  renders no such variable at all — which is what makes "set and empty" a
  distinguishable state rather than a tautology.
- **The pinentry choice is not in the systemd unit.** It lands in
  `~/.gnupg/gpg-agent.conf` as a `pinentry-program` line; the rendered unit says
  nothing about it.

One assertion needed a **counterfactual** to be assertable at all.
`programs.ssh.enableDefaultConfig = false` is a claim about what is *absent*:
turning it back on adds `AddKeysToAgent`, `Compression`, `ForwardAgent`,
`HashKnownHosts`, `ServerAliveCountMax`, `ServerAliveInterval` and
`UserKnownHostsFile`. So the absence of those tells the two cases apart, where the
presence of `ControlMaster` does not.

### Two nodes, and the one claim that needed a counterfactual it could not have

`home-desktop` carries two nodes. The profile **alone** is the `#50` proving
proper, and isolation is the point: a proving named `home-desktop` that went red
because something in enginseer broke would be a bad diagnosis. The **composed**
node exists for a single claim, written in `cogitator/home/desktop.nix`:

```nix
# Graphical pinentry for gpg-agent. Overrides the headless-safe default set
# by cogitator-enginseer; inert if gpg-agent is not enabled.
services.gpg-agent.pinentry.package = lib.mkForce pkgs.pinentry-qt;
```

The first half is a priority contest between two cogitators, and neither node
alone can show it: `enginseer` asserts the `pinentry-curses` side, `composed`
asserts the `pinentry-qt` side.

**The second half — "inert if gpg-agent is not enabled" — is deliberately not
asserted in a VM.** The plan called for checking that no `gpg-agent` user unit
exists on the desktop-alone node. Measured against the reference node: it has no
such unit either, because `services.gpg-agent.enable` is `false` without any
cogitator. The assertion would be green whatever STC did. Inertness is an
*evaluation* property — desktop alone sets `pinentry.package` to `pinentry-qt`
while `gpg-agent.enable` stays `false`, so nothing consumes the value — and
reading that from inside the VM would mean interpolating the option out of the
same evaluation that built the node. Same treatment as `docker-server`'s negative
case and as `boot.zfs.devNodes` in `sarcophagus-aws`.

Two more candidates measurement corrected before they were written:

- **zen-browser's binary is `zen-beta`, not `zen`** — the cogitator imports
  `inputs.zen-browser.homeModules.beta`. Asserting the obvious name would have
  been red. It is also the only one of the three relics that renders no file at
  all, so the user profile is the only place it is observable, which is what
  `useUserPackages` buys this proving.
- **The nerd fonts are not reachable at the obvious path.** They are what
  `stc.relics.gui.kitty.fonts.enable` (default true) installs — the only option
  of STC's own across these three relics, the other two doing nothing but setting
  `programs.<x>.enable`. But `environment.pathsToLink` carries no `/share/fonts`
  entry, so `/etc/profiles/per-user/<u>/share/fonts` is never populated: the
  fonts sit inside the `home-manager-path` derivation, which
  `~/.config/fontconfig/conf.d/10-hm-fonts.conf` points at. So the assertion goes
  through `fc-list` — the behavioural question, *can the session find these
  fonts*, is both the right one and the only one with a true answer.

### Scope limit — configuration, not a live agent

The proving does not assert that `gpg-agent` is *running*. It is a user unit and
would need a live user session; what the cogitator decides is which pinentry the
agent carries, and that is readable in the rendered configuration. The running
agent is upstream's.

Also not asserted: the mere presence of packages on `PATH`. A list of packages
proves that a list of packages was written.

### Scope limit — the GUI relics are proven configured, not launched

`home-desktop` brings up no graphical session, the same limit the `plasma`
proving states for its own reasons. kitty, ghostty and Zen Browser are therefore
proven **installed and configured** — their files rendered, their binaries on the
profile, their fonts visible to fontconfig — and not proven to *start*. Launching
three GPU-oriented terminals and a browser in a VM would measure upstream's
packaging rather than STC's wiring, which is all these three relics contribute.

## Booting a real image — the external-image pattern

Twelve of the fourteen provings let the test driver synthesise a node. `sarcophagus-kvm`
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

`provings/sarcophagus-aws.nix` reuses this pattern, and exactly two things
differ. The image is raw rather than qcow2 — measured in
`make-single-disk-zfs-image.nix`, `format = "raw"` maps to the `.img` suffix, so
the overlay is taken over `nixos.root.img` with `-F raw`. And the overlay is
given a **size**: 8 GiB over a 5 GiB image, so partition 3 ends short of the
end of the device and `stc-grow-pool` has something to grow. Three sizes are in
play and collapsing any two gets the arithmetic wrong — measured on the
artefact, the ZFS partition is 4096 MiB (`rootSize`), the image *file* is
5120 MiB (upstream sizes it at `bootSize + rootSize`, and `bootSize` defaults to
1024), and the virtual disk is 8 GiB. The proving's threshold is therefore
anchored on the **pool**, which goes from p3's 3.999 GiB to 6.75 GiB. That is an EC2
instance on an EBS volume larger than its AMI, and it is the one claim neither
`dreadnought` (which only reads the *string* of that script) nor
`sarcophagus-kvm` (whose disk is exactly the size of its image) can reach.
Measured on the bench: the pool comes up at 6.75 GiB.

The five concession lines and the `qemu-img` block are **copied** into the second
proving rather than factored out. Two occurrences do not make an abstraction, and
a shared helper would hide precisely the lines a reader needs in front of them to
trust the bench. If a third sarcophagus arrives, factor it then, with three cases
in view.

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

**What `sarcophagus-aws` changed about this table, and what it did not.** Booting
the real image lifts the framework limits above: the pool import, the dataset
mounts, the boot device and — the point of that proving — the runtime growth of
the pool are all asserted there. Three gaps are *not* lifted, and were re-measured
rather than assumed:

- **The serial console** stays uncovered. The getty is `lib.mkDefault` since #45,
  so it loses an ordinary priority contest to the test instrumentation instead of
  colliding with it — which is what made a proving of this profile possible at all,
  but it still means no getty runs. The baud-rate string is a subtler case: under
  the external-image pattern `directBoot` is off and the kernel command line comes
  from the image's own GRUB, so `virtualisation.qemu.consoles` no longer reaches
  it and the string *might* discriminate there. Establishing that would mean
  building a second image without the relic, which the proving does not pay for —
  so it is not asserted, rather than asserted on an unverified premise.
- **The AWS NTP endpoint** stays uncovered, for a reason that survives the
  external-image pattern: `services.timesyncd.enable` is measured `false` on a
  bare node, a ZFS-only node *and* the STC node, so no
  `/etc/systemd/timesyncd.conf` is rendered at all and there is nothing to read
  `169.254.169.123` from. It is `qemu-vm.nix:1489` that turns it off — a bare
  `false` at normal priority, commented *"Don't run ntpd in the guest"* — and not
  `nixos-test-base.nix`, which never mentions timesyncd.
- **`boot.zfs.devNodes`** (`/dev`, against the default `/dev/disk/by-id`)
  discriminates in evaluation and cannot be asserted on this bench at all: the
  only runtime reading would be the store path of a unit script interpolated from
  the same evaluation, which is a tautology — and a virtio disk *does* have by-id
  entries, so the default would import the pool just as well. The bench cannot
  tell the relic from the default.

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
