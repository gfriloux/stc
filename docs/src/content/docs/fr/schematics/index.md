---
title: Schématics
description: Exemples complets de flakes consommateurs — lis-les pour comprendre comment les pièces STC s'assemblent en pratique.
sidebar:
  order: 0
---

Un schématic est un flake consommateur complet et fonctionnel. Ce n'est pas une
bibliothèque, pas un exemple abstrait — c'est un vrai `flake.nix` avec tous les
inputs requis, les modules et la configuration que tu peux copier et adapter.

Les schématics remplissent deux objectifs :

1. **Apprentissage** — voir comment les modules STC sont câblés ensemble dans un scénario réaliste
2. **Point de départ** — copier le schématic qui correspond à ton cas d'usage et l'adapter

## Comment lire un schématic

Chaque schématic se compose de :

- `flake.nix` — le flake racine avec les inputs et `nixosConfigurations`
- Un ou plusieurs fichiers de modules (`qcow2.nix`, `image.nix`) — overrides du builder d'image
- `Justfile` — exécuteur de tâches avec des recettes standard (build, run, publish, ssh)

Le `flake.nix` d'un schématic montre exactement quels modules STC sont importés et
quelles valeurs de configuration ils nécessitent. Les commentaires expliquent les
choix non évidents.

Chaque schématic contient un Justfile avec les recettes build / run / ssh.

## Schématics disponibles

| Schématic | Ce qu'il construit | Composants STC clés |
|-----------|-------------------|---------------------|
| `local-vm` | VM de développement QEMU/KVM avec ZFS + impermanence | relics-boot, relics-zfs, relics-impermanence, cogitator-hardening, cogitator-vm, layout zfs-local-vm |
| `aws-ami` | AMI AWS EC2 avec ZFS + impermanence + durcissement | relics-boot, relics-zfs, relics-aws, relics-impermanence, cogitator-hardening, layout zfs-local-vm |

## Voir aussi

- [Schématic local-vm](/fr/schematics/local-vm/)
- [Schématic aws-ami](/fr/schematics/aws-ami/)
