---
title: Gaming
description: cogitator-gaming — AMD GPU + Pipewire + Steam en une seule option pour les machines gaming NixOS.
---

**Module :** `stc.nixosModules.cogitator-gaming`

**Option d'activation :** `stc.cogitator.gaming.enable`

Compose la relique AMD GPU et la relique Pipewire, puis active Steam via l'option
NixOS `programs.steam`. Une seule option configure une base gaming complète pour
une machine avec GPU AMD.

## Ce que ça compose

| Relique / option | Ce que ça fait |
|------------------|----------------|
| `relics-amd-gpu` | VDPAU, VAAPI, pilotes GPU 32 bits |
| `relics-pipewire` | RTKit + ALSA 32 bits + compat PulseAudio |
| `programs.steam.enable = true` | Steam avec les wrappers et bibliothèques 32 bits adaptés |

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.cogitator.gaming.enable` | bool | `false` | Active le profil gaming |
| `stc.cogitator.gaming.steam.remotePlay` | bool | `false` | Ouvrir les ports pare-feu pour Steam Remote Play |

Les options des reliques sous-jacentes restent réglables :

```nix
stc.relics.amdGpu.initrd = true;   # framebuffer KMS précoce au démarrage
```

## Compatibilité avec le durcissement

Si `cogitator-hardening` ou des reliques de durcissement individuelles sont
actives, ajoute ces options — sans elles, Steam ne peut pas démarrer :

```nix
stc.relics.hardening.kernel.gaming = true;      # Steam nécessite les user namespaces
stc.relics.hardening.filesystem.gaming = true;  # Wine/Proton ont besoin de exec dans /tmp et /dev/shm
stc.relics.hardening.filesystem.shmSize = "4G"; # DXVK/VKD3D ont besoin de plus que 256M
```

## Paquets Home Manager

Ce cogitator gère uniquement la configuration système du gaming. Ajoute tes
propres paquets dans ta configuration Home Manager :

```nix
# home.nix
home.packages = with pkgs; [
  heroic           # launcher GOG / Epic / Amazon Games
  protonup-ng      # gestionnaire de versions Proton-GE
  winetricks
  wineWow64Packages.staging

  # Émulateurs — ajoute selon tes besoins :
  pcsx2            # PS2
  ryubing          # Nintendo Switch (fork Ryujinx)
  scummvm
  dosbox-x
  scanmem          # scanner mémoire / cheat engine
];
```

## Exemple d'utilisation

```nix
modules = [
  stc.nixosModules.cogitator-gaming
  stc.nixosModules.relics-hardening-kernel      # optionnel
  stc.nixosModules.relics-hardening-filesystem  # optionnel
  ./configuration.nix
];

# configuration.nix
{
  stc.cogitator.gaming.enable = true;

  # Si le durcissement est actif :
  stc.relics.hardening.kernel.enable = true;
  stc.relics.hardening.kernel.gaming = true;
  stc.relics.hardening.filesystem.enable = true;
  stc.relics.hardening.filesystem.gaming = true;
  stc.relics.hardening.filesystem.shmSize = "4G";
}
```

## Voir aussi

- [Relique AMD GPU](/stc/fr/relics/amd-gpu/) — relique GPU autonome
- [Relique Pipewire](/stc/fr/relics/pipewire/) — relique audio autonome
- [Reliques de durcissement](/stc/fr/relics/hardening/) — options de compatibilité gaming
- [cogitator-plasma](/stc/fr/cogitator/plasma/) — profil bureau Plasma, composable avec cogitator-gaming
