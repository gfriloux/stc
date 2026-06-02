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
- `Justfile` — exécuteur de tâches avec des recettes standard (build, deploy, run, ssh)

Le `flake.nix` d'un schématic montre exactement quels modules STC sont importés et
quelles valeurs de configuration ils nécessitent. Les commentaires expliquent les
choix non évidents.

Chaque schématic contient un Justfile avec les recettes build / run / ssh.

## Schématics disponibles

| Schématic | Ce qu'il construit | Composants STC clés |
|-----------|-------------------|---------------------|
| `local-vm` | VM de développement QEMU/KVM avec ZFS + impermanence | `cogitator-sarcophagus-kvm`, `cogitator-vm` |
| `aws-ami` | AMI AWS EC2 avec ZFS + impermanence + durcissement | `cogitator-sarcophagus-aws` |
| `dreadnought` | Instance EC2 NixOS gérée via deploy-rs | `cogitator-dreadnought` |

## Voir aussi

- [Schématic local-vm](/stc/fr/schematics/local-vm/)
- [Schématic aws-ami](/stc/fr/schematics/aws-ami/)
- [Schématic dreadnought](/stc/fr/schematics/dreadnought/)
