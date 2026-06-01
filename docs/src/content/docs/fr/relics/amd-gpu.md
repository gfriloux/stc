---
title: AMD GPU
description: Relique AMD GPU — VDPAU, VAAPI, support 32 bits et KMS précoce optionnel.
---

**Module :** `stc.nixosModules.relics-amd-gpu`

**Option d'activation :** `stc.amdGpu.enable`

Configure l'accélération graphique matérielle pour les GPU AMD. Active la pile de
pilotes 32 bits requise par Steam et DXVK/Proton, et installe les bibliothèques
VDPAU et VAAPI pour le décodage vidéo matériel.

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.amdGpu.enable` | bool | `false` | Active le support GPU AMD |
| `stc.amdGpu.initrd` | bool | `false` | Charge amdgpu dans l'initrd pour le framebuffer KMS précoce |

### `initrd`

Quand `true`, charge le module noyau `amdgpu` pendant la phase initrd. Cela donne
un framebuffer graphique tôt au démarrage — utile pour les animations Plymouth,
les invites de mot de passe LUKS, et toute autre sortie affichée avant la connexion.

Non nécessaire pour un usage desktop normal. À n'activer que si tu as besoin
d'un affichage avant la fin de la séquence de démarrage NixOS complète.

## Ce que ça configure

```
hardware.graphics.enable = true
hardware.graphics.enable32Bit = true
hardware.graphics.extraPackages = [ libvdpau libva-vdpau-driver ]
boot.initrd.kernelModules = [ "amdgpu" ]   # seulement si initrd = true
```

## Exemple d'utilisation

```nix
modules = [
  stc.nixosModules.relics-amd-gpu
  ./configuration.nix
];

# configuration.nix
{
  stc.amdGpu.enable = true;
  stc.amdGpu.initrd = true;  # optionnel — KMS précoce
}
```

## Voir aussi

- [cogitator-gaming](/stc/fr/cogitator/gaming/) — compose cette relique avec Pipewire et Steam
- [Pipewire](/stc/fr/relics/pipewire/) — relique audio, se marie bien avec AMD GPU sur machines gaming
