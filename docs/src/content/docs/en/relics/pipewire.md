---
title: Pipewire
description: Pipewire audio relic — RTKit real-time scheduling, ALSA 32-bit, and PulseAudio compatibility.
---

**Module:** `stc.nixosModules.relics-pipewire`

**Enable option:** `stc.relics.pipewire.enable`

Configures Pipewire as the system audio server. Replaces PulseAudio, enables
RTKit for real-time scheduling priority, and activates both ALSA and PulseAudio
compatibility layers so all existing applications work without reconfiguration.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.pipewire.enable` | bool | `false` | Enable Pipewire audio server |

## What it configures

```
security.rtkit.enable = true
services.pulseaudio.enable = false
services.pipewire.enable = true
services.pipewire.alsa.enable = true
services.pipewire.alsa.support32Bit = true
services.pipewire.pulse.enable = true
```

**RTKit** grants Pipewire real-time scheduling priority on demand, which reduces
audio glitches under CPU load.

**32-bit ALSA** is required by Steam and 32-bit Wine applications. Without it,
those applications cannot produce audio.

**PulseAudio compat** (`pulse.enable`) provides a PulseAudio socket, so
applications that only speak PulseAudio continue working transparently.

## Usage Example

```nix
modules = [
  stc.nixosModules.relics-pipewire
  ./configuration.nix
];

# configuration.nix
{ stc.relics.pipewire.enable = true; }
```

## See Also

- [cogitator-plasma](/stc/en/cogitator/plasma/) — composes this relic with the Plasma 6 desktop
- [cogitator-gaming](/stc/en/cogitator/gaming/) — composes this relic with AMD GPU and Steam
- [AMD GPU](/stc/en/relics/amd-gpu/) — the 32-bit GPU driver relic, pairs with Pipewire for gaming
