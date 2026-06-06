---
title: Networking
description: Configuration réseau de base — DHCP sur toutes les interfaces, DNS Quad9 par défaut.
---

**Module :** `stc.nixosModules.relics-networking`

Valeurs réseau sensées. DHCP sur toutes les interfaces, DNS Quad9.

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.relics.networking.enable` | bool | `false` | Active la configuration réseau de base |
| `stc.relics.networking.domain` | `null \| string` | `null` | Domaine de recherche DNS. `null` signifie qu'aucun domaine n'est défini |
| `stc.relics.networking.nameservers` | liste de strings | `[ "9.9.9.9" "149.112.112.112" ]` | Résolveurs DNS |

## Ce qu'elle fait

Lorsqu'elle est activée :

- Pose `networking.usePredictableInterfaceNames = true` (mkDefault — surchargeable)
- Pose `networking.useDHCP = true` (mkDefault — surcharge par interface si besoin)
- Applique `nameservers` à `networking.nameservers`
- Applique `domain` à `networking.domain` lorsqu'il n'est pas null

## Pourquoi Quad9 ?

Quad9 (`9.9.9.9` / `149.112.112.112`) est le défaut pour trois raisons :

1. **Vie privée** — pas de journalisation des requêtes, pas de revente de données
2. **Sécurité** — bloque les domaines malveillants connus via des flux de renseignement sur les menaces
3. **DNSSEC** — valide les réponses DNS, prévient le spoofing

Change `nameservers` si ton modèle de menace diffère, si ton organisation exploite
un résolveur interne, ou si tu opères dans une juridiction où Quad9 est bloqué.

## Exemple d'utilisation

```nix
# flake.nix
modules = [
  stc.nixosModules.relics-networking
  ./configuration.nix
];

# configuration.nix
{
  stc.relics.networking.enable = true;

  # Surcharges optionnelles
  stc.relics.networking.domain = "corp.example.com";
  stc.relics.networking.nameservers = [ "192.168.1.1" ];

  # Au niveau NixOS : le hostname et le hostId ZFS
  networking.hostName = "my-server";
  networking.hostId = "a1b2c3d4";
}
```

:::tip[DHCP par interface]
`useDHCP` est posé avec `mkDefault`. Pour désactiver le DHCP globalement et
configurer les interfaces individuellement, pose `networking.useDHCP = false`
dans ta configuration puis déclare chaque interface explicitement.
:::
