---
title: Pipewire
description: Relique Pipewire — ordonnancement temps-réel RTKit, ALSA 32 bits et compatibilité PulseAudio.
---

**Module :** `stc.nixosModules.relics-pipewire`

**Option d'activation :** `stc.pipewire.enable`

Configure Pipewire comme serveur audio système. Remplace PulseAudio, active RTKit
pour la priorité d'ordonnancement temps-réel, et active les couches de compatibilité
ALSA et PulseAudio pour que toutes les applications existantes fonctionnent sans
reconfiguration.

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.pipewire.enable` | bool | `false` | Active le serveur audio Pipewire |

## Ce que ça configure

```
security.rtkit.enable = true
services.pulseaudio.enable = false
services.pipewire.enable = true
services.pipewire.alsa.enable = true
services.pipewire.alsa.support32Bit = true
services.pipewire.pulse.enable = true
```

**RTKit** accorde à Pipewire une priorité d'ordonnancement temps-réel à la
demande, ce qui réduit les coupures audio sous charge CPU.

**ALSA 32 bits** est requis par Steam et les applications Wine 32 bits. Sans lui,
ces applications ne peuvent pas produire de son.

**Compat PulseAudio** (`pulse.enable`) fournit un socket PulseAudio, pour que
les applications qui ne parlent que PulseAudio continuent de fonctionner de façon
transparente.

## Exemple d'utilisation

```nix
modules = [
  stc.nixosModules.relics-pipewire
  ./configuration.nix
];

# configuration.nix
{ stc.pipewire.enable = true; }
```

## Voir aussi

- [cogitator-plasma](/fr/cogitator/plasma/) — compose cette relique avec le bureau Plasma 6
- [cogitator-gaming](/fr/cogitator/gaming/) — compose cette relique avec AMD GPU et Steam
- [AMD GPU](/fr/relics/amd-gpu/) — la relique pilote GPU 32 bits, se marie avec Pipewire pour le gaming
