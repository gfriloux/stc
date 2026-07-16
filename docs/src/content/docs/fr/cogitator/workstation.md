---
title: Poste de travail
description: cogitator-workstation — socle de poste durci (desktop + durcissement + YubiKey) en une seule option.
---

**Module :** `stc.nixosModules.cogitator-workstation`

**Option d'activation :** `stc.cogitator.workstation.enable`

Le socle de poste de travail durci, inspiré des *postes* ANSSI/Sécurix. Il compose
le socle de sécurité agnostique du DE — durcissement noyau + réseau + blacklist de
modules, plus le support YubiKey — avec un environnement de bureau choisi par
l'option `desktop`. Au lieu que chaque host desktop réassemble sa propre sécurité,
tu actives un seul profil.

L'environnement de bureau reste orthogonal : ajouter i3 demain, c'est un nouveau
`cogitator-i3` et une valeur `desktop` de plus — le socle ne change pas.

## Ce qu'il compose

| Relique / profil | Ce que ça fait |
|------------------|----------------|
| `relics-hardening-kernel` | Durcissement sysctl noyau (toujours actif) |
| `relics-hardening-network` | Durcissement sysctl réseau (toujours actif) |
| `relics-hardening-modules` | Blacklist de modules noyau à risque / inutilisés (toujours actif) |
| `relics-hardening-filesystem` | /tmp noexec, /proc hidepid, /dev/shm restreint (toggle) |
| `relics-yubikey-system` | pcscd + règles udev (toggle) |
| `cogitator-plasma` | Bureau KDE Plasma 6 + Pipewire (via `desktop = "plasma"`) |

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.cogitator.workstation.enable` | bool | `false` | Active le profil poste de travail |
| `stc.cogitator.workstation.desktop` | enum `"plasma"` | `"plasma"` | Environnement de bureau. Un poste a toujours un DE ; une machine sans DE est un serveur. Extensible à `"i3"`. |
| `stc.cogitator.workstation.yubikey` | bool | `true` | Active le support YubiKey. Mettre `false` sur un poste sans clé. |
| `stc.cogitator.workstation.hardening.filesystem.enable` | bool | `true` | Durcissement filesystem. Mettre `false` si hidepid=2 gêne polkit / D-Bus utilisateur et que tu ne les as pas ajoutés au groupe `proc`. |
| `stc.cogitator.workstation.hardening.filesystem.gaming` | bool | `false` | Retire `noexec` de /tmp et /dev/shm pour que Steam/Proton tournent. Garde nosuid/nodev et hidepid. |

Les autres options des reliques restent tunables directement via
`stc.relics.hardening.*` (`tmpSize`, `shmSize`, …).

## Ce qu'il ne fait PAS (par choix)

- **Pas de SSH.** Aucun sshd n'est démarré. Pour l'accès distant, active-le
  toi-même : `stc.relics.hardening.ssh.enable = true;`.
- **Pas de matériel gaming.** AMD GPU + Steam vivent dans
  [`cogitator-gaming`](/stc/fr/cogitator/gaming/), empilé séparément. Ce profil ne
  gère que le versant *exec filesystem* du gaming.

## Exemple d'utilisation

Un poste KDE standard :

```nix
# flake.nix
modules = [
  stc.nixosModules.cogitator-workstation
  ./configuration.nix
];

# configuration.nix
{
  stc.cogitator.workstation.enable = true;
  # desktop = "plasma" et yubikey = true sont les défauts.
}
```

Un poste de jeu KDE (empile le profil gaming pour GPU + Steam) :

```nix
{
  stc.cogitator.workstation.enable = true;
  stc.cogitator.workstation.hardening.filesystem.gaming = true; # Proton a besoin d'exec

  stc.cogitator.gaming.enable = true;             # AMD GPU + Steam
  stc.relics.hardening.filesystem.shmSize = "4G"; # DXVK/VKD3D ont besoin de plus que 256M
}
```

:::caution[hidepid et desktops]
Le durcissement filesystem pose `hidepid=2`, qui masque les processus des autres
utilisateurs à polkit, aux agents D-Bus utilisateur et à certains exporters. Seul
`systemd-logind` est câblé d'office dans le groupe `proc`. Si polkit/D-Bus
dysfonctionne, ajoute les services concernés au groupe `proc` via
`systemd SupplementaryGroups`, ou mets
`stc.cogitator.workstation.hardening.filesystem.enable = false`.
:::

## Voir aussi

- [Profil bureau Plasma](/stc/fr/cogitator/plasma/) — le DE que ce profil sélectionne
- [Profil gaming](/stc/fr/cogitator/gaming/) — GPU + Steam, empilé séparément
- [Reliques de durcissement](/stc/fr/relics/hardening/) — le socle de sécurité en détail
