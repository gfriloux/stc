---
title: Workstation
description: cogitator-workstation — hardened personal-workstation baseline (desktop + hardening + YubiKey) in a single enable option.
---

**Module:** `stc.nixosModules.cogitator-workstation`

**Enable option:** `stc.cogitator.workstation.enable`

The hardened personal-workstation baseline, inspired by ANSSI/Sécurix *postes*.
It composes the DE-agnostic security socle — kernel + network + module-blacklist
hardening plus YubiKey support — with a desktop environment selected by the
`desktop` option. Instead of each desktop host re-assembling its own security,
you enable one profile.

The desktop environment stays orthogonal: adding i3 tomorrow is a new
`cogitator-i3` and an extra `desktop` value — the socle does not change.

## What it composes

| Relic / profile | What it does |
|-----------------|-------------|
| `relics-hardening-kernel` | Kernel sysctl hardening (always on) |
| `relics-hardening-network` | Network sysctl hardening (always on) |
| `relics-hardening-modules` | Blacklist high-risk / unused kernel modules (always on) |
| `relics-hardening-filesystem` | /tmp noexec, /proc hidepid, /dev/shm restricted (toggle) |
| `relics-yubikey-system` | pcscd + udev rules (toggle) |
| `cogitator-plasma` | KDE Plasma 6 desktop + Pipewire (via `desktop = "plasma"`) |

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.cogitator.workstation.enable` | bool | `false` | Enable the workstation profile |
| `stc.cogitator.workstation.desktop` | enum `"plasma"` | `"plasma"` | Desktop environment. A workstation always has a DE; a machine without one is a server. Extensible to `"i3"`. |
| `stc.cogitator.workstation.yubikey` | bool | `true` | Enable YubiKey system support. Set `false` on a workstation with no key. |
| `stc.cogitator.workstation.hardening.filesystem.enable` | bool | `true` | Filesystem hardening. Set `false` if hidepid=2 disturbs polkit / user D-Bus and you have not wired them into the `proc` group. |
| `stc.cogitator.workstation.hardening.filesystem.gaming` | bool | `false` | Drop `noexec` on /tmp and /dev/shm so Steam/Proton can run. Keeps nosuid/nodev and hidepid. |

Other relic options remain tunable directly via `stc.relics.hardening.*`
(`tmpSize`, `shmSize`, …).

## What it does NOT do (by design)

- **No SSH.** No sshd is started. If you want remote access, enable it yourself:
  `stc.relics.hardening.ssh.enable = true;`.
- **No gaming hardware.** AMD GPU + Steam live in
  [`cogitator-gaming`](/stc/en/cogitator/gaming/), stacked separately. This
  profile only handles the *filesystem-exec* side of gaming.

## Usage Example

A standard KDE workstation:

```nix
# flake.nix
modules = [
  stc.nixosModules.cogitator-workstation
  ./configuration.nix
];

# configuration.nix
{
  stc.cogitator.workstation.enable = true;
  # desktop = "plasma" and yubikey = true are the defaults.
}
```

A gaming KDE workstation (stack the gaming profile for GPU + Steam):

```nix
{
  stc.cogitator.workstation.enable = true;
  stc.cogitator.workstation.hardening.filesystem.gaming = true; # Proton needs exec

  stc.cogitator.gaming.enable = true;             # AMD GPU + Steam
  stc.relics.hardening.filesystem.shmSize = "4G"; # DXVK/VKD3D need more than 256M
}
```

:::caution[hidepid and desktops]
Filesystem hardening sets `hidepid=2`, which hides other users' processes from
polkit, user D-Bus agents and some exporters. Only `systemd-logind` is wired into
the `proc` group out of the box. If polkit/D-Bus misbehave, either add the
affected services to the `proc` group via `systemd SupplementaryGroups`, or set
`stc.cogitator.workstation.hardening.filesystem.enable = false`.
:::

## See Also

- [Plasma desktop profile](/stc/en/cogitator/plasma/) — the DE this profile selects
- [Gaming profile](/stc/en/cogitator/gaming/) — GPU + Steam, stacked separately
- [Hardening relics](/stc/en/relics/hardening/) — the security socle in detail
