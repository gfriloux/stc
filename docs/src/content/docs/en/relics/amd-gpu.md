---
title: AMD GPU
description: AMD GPU relic — VDPAU, VAAPI, 32-bit driver support, and optional early KMS framebuffer.
---

**Module:** `stc.nixosModules.relics-amd-gpu`

**Enable option:** `stc.amdGpu.enable`

Configures hardware graphics acceleration for AMD GPUs. Enables the 32-bit driver
stack required by Steam and DXVK/Proton, and installs VDPAU and VAAPI libraries
for hardware video decoding.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.amdGpu.enable` | bool | `false` | Enable AMD GPU support |
| `stc.amdGpu.initrd` | bool | `false` | Load amdgpu in the initrd for early KMS framebuffer |

### `initrd`

When `true`, loads the `amdgpu` kernel module during the initrd phase. This gives
a graphical framebuffer early in boot — useful for Plymouth animations, LUKS
passphrase prompts, and other pre-login display output.

Not required for normal desktop use. Only enable it if you need display output
before the full NixOS boot sequence completes.

## What it configures

```
hardware.graphics.enable = true
hardware.graphics.enable32Bit = true
hardware.graphics.extraPackages = [ libvdpau libva-vdpau-driver ]
boot.initrd.kernelModules = [ "amdgpu" ]   # only when initrd = true
```

## Usage Example

```nix
modules = [
  stc.nixosModules.relics-amd-gpu
  ./configuration.nix
];

# configuration.nix
{
  stc.amdGpu.enable = true;
  stc.amdGpu.initrd = true;  # optional — early KMS
}
```

## See Also

- [cogitator-gaming](/en/cogitator/gaming/) — composes this relic with Pipewire and Steam
- [Pipewire](/en/relics/pipewire/) — audio relic, pairs well with AMD GPU on gaming machines
