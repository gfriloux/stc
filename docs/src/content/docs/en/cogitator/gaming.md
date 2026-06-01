---
title: Gaming
description: cogitator-gaming — AMD GPU + Pipewire + Steam in a single enable option for NixOS gaming machines.
---

**Module:** `stc.nixosModules.cogitator-gaming`

**Enable option:** `stc.cogitator.gaming.enable`

Composes the AMD GPU relic and the Pipewire relic, then enables Steam via the
NixOS `programs.steam` option. One enable option sets up a complete gaming
foundation for an AMD GPU machine.

## What it composes

| Relic / option | What it does |
|----------------|-------------|
| `relics-amd-gpu` | VDPAU, VAAPI, 32-bit GPU drivers |
| `relics-pipewire` | RTKit + ALSA 32-bit + PulseAudio compat |
| `programs.steam.enable = true` | Steam with proper wrappers and 32-bit libs |

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.cogitator.gaming.enable` | bool | `false` | Enable the gaming profile |
| `stc.cogitator.gaming.steam.remotePlay` | bool | `false` | Open firewall ports for Steam Remote Play |

Underlying relic options remain tunable:

```nix
stc.amdGpu.initrd = true;   # early KMS framebuffer at boot
```

## Hardening compatibility

If `cogitator-hardening` or individual hardening relics are active, add these
options — without them, Steam cannot start:

```nix
stc.hardening.kernel.gaming = true;      # Steam needs user namespaces
stc.hardening.filesystem.gaming = true;  # Wine/Proton need exec in /tmp and /dev/shm
stc.hardening.filesystem.shmSize = "4G"; # DXVK/VKD3D need more than 256M
```

## Home Manager packages

This cogitator manages the system-level gaming setup only. Add your own packages
in your Home Manager configuration:

```nix
# home.nix
home.packages = with pkgs; [
  heroic           # GOG / Epic / Amazon Games launcher
  protonup-ng      # Proton-GE version manager
  winetricks
  wineWow64Packages.staging

  # Emulators — add what you need:
  pcsx2            # PS2
  ryubing          # Nintendo Switch (Ryujinx fork)
  scummvm
  dosbox-x
  scanmem          # memory scanner / cheat engine
];
```

## Usage Example

```nix
modules = [
  stc.nixosModules.cogitator-gaming
  stc.nixosModules.relics-hardening-kernel   # optional
  stc.nixosModules.relics-hardening-filesystem  # optional
  ./configuration.nix
];

# configuration.nix
{
  stc.cogitator.gaming.enable = true;

  # If hardening is active:
  stc.hardening.kernel.enable = true;
  stc.hardening.kernel.gaming = true;
  stc.hardening.filesystem.enable = true;
  stc.hardening.filesystem.gaming = true;
  stc.hardening.filesystem.shmSize = "4G";
}
```

## See Also

- [AMD GPU relic](/stc/en/relics/amd-gpu/) — standalone GPU relic
- [Pipewire relic](/stc/en/relics/pipewire/) — standalone audio relic
- [Hardening relics](/stc/en/relics/hardening/) — gaming compatibility options
- [cogitator-plasma](/stc/en/cogitator/plasma/) — Plasma desktop profile, composable with cogitator-gaming
