---
title: Dev Shells
description: Sept environnements de développement pré-construits couvrant Ansible, Terraform, la documentation, la construction de VMs et les opérations NixOS.
---

STC fournit sept dev shells. Référence-les depuis ton propre flake pour donner à ton
projet un environnement de développement reproductible sans maintenir les définitions
d'outils toi-même.

## Comment utiliser un shell

Dans un flake classique :

```nix
outputs = { stc, ... }: {
  devShells.x86_64-linux.default = stc.devShells.x86_64-linux.ansible;
};
```

Avec flake-parts :

```nix
perSystem = { system, ... }: {
  devShells.default = stc.devShells.${system}.ansible;
};
```

Puis entre dans l'environnement :

```bash
nix develop
```

Tous les shells installent une configuration `pre-commit` à l'entrée (si elle n'est
pas déjà présente) et câblent les hooks git automatiquement dans un dépôt git.

---

## ansible

Fournit trois versions d'Ansible simultanément pour tester sur des environnements mixtes.

| Outil | Utilité |
|-------|---------|
| `ansible` | Dernière version de nixpkgs unstable |
| `ansible_2_16` | Version fixée (nixos-25.05), correctement enveloppée avec PYTHONPATH |
| `ansible_2_17` | Version fixée (nixos-25.05), correctement enveloppée avec PYTHONPATH |
| `ansible-lint` | Lint des playbooks |
| `ansible-recap` | Formateur de résumé d'exécution |
| `rbw` | CLI Bitwarden (accès au coffre pendant les exécutions) |
| `openssh_gssapi` | SSH avec support Kerberos/GSSAPI |
| `shellcheck` + `shfmt` | Lint des scripts shell |
| `just` | Exécuteur de tâches |
| `gum` | Prompts CLI interactifs |
| `pre-commit` | Exécuteur de hooks git |

À l'entrée dans le shell, les versions installées sont affichées :

```
[stc:ansible] Operational. Three ansible versions at your service.
  ansible         ansible [core 2.18.x]
  ansible_2_16    ansible [core 2.16.x]
  ansible_2_17    ansible [core 2.17.x]
```

---

## terraform

Environnement Infrastructure as Code avec lint, analyse de sécurité, et génération
de documentation.

| Outil | Utilité |
|-------|---------|
| `terraform` | Outil IaC principal |
| `terragrunt` | Wrapper DRY pour les déploiements multi-environnements |
| `terraform-docs` | Génération automatique de documentation de modules |
| `tflint` | Lint (syntaxe dépréciée, erreurs de type) |
| `tfsec` | Analyse de sécurité statique |
| `just` | Exécuteur de tâches |
| `glow` | Rendu Markdown |
| `pre-commit` | Exécuteur de hooks git |

:::note[Licence BSL]
`terraform` de nixpkgs est la version Business Source License (BSL)
(HashiCorp a changé la licence en 1.6.0). Si ton organisation exige une
licence open-source, utilise `opentofu` à la place et ajuste ton flake.
:::

---

## mdbook

Générateur de site de documentation en Rust.

| Outil | Utilité |
|-------|---------|
| `mdbook` | Construire et servir le livre |
| `rumdl` | Lint Markdown |
| `just` | Exécuteur de tâches |
| `glow` | Aperçu Markdown dans le terminal |
| `pre-commit` | Exécuteur de hooks git |

---

## mkdocs

Documentation Python avec MkDocs Material et son écosystème de plugins.

| Outil | Utilité |
|-------|---------|
| `pipenv` | Gestionnaire d'environnement et de dépendances Python |
| `python312` + `pip` | Runtime Python |
| `rumdl` | Lint Markdown (niveau Nix) |
| `glow` | Aperçu Markdown |
| `pre-commit` | Exécuteur de hooks git |

À l'entrée dans le shell, `pipenv install` s'exécute automatiquement si un `Pipfile`
est présent. La première exécution nécessite un accès réseau. Les suivantes utilisent
le lockfile.

---

## zensical

Documentation Python pour le générateur Zensical, structurée de manière identique
à mkdocs.

| Outil | Utilité |
|-------|---------|
| `pipenv` | Gestionnaire d'environnement et de dépendances Python |
| `python312` + `pip` | Runtime Python |
| `rumdl` | Lint Markdown (niveau Nix) |
| `glow` | Aperçu Markdown |
| `pre-commit` | Exécuteur de hooks git |

---

## vm

Construire et exécuter des images VM NixOS. L'ensemble d'outils couvre le cycle complet
construire-inspecter-démarrer.

| Outil | Utilité |
|-------|---------|
| `qemu` | Démarrer des images (qemu-img pour l'inspection, qemu-system pour le démarrage) |
| `nix-tree` | Inspecter les tailles de fermetures |
| `nvd` | Comparer les générations NixOS |
| `nix-output-monitor` | Meilleur affichage de `nix build` |
| `alejandra` | Formateur Nix |
| `statix` | Lint Nix pour les antipatterns |
| `deadnix` | Trouver les bindings inutilisés |
| `just` | Exécuteur de tâches |
| `pre-commit` | Exécuteur de hooks git |

À l'entrée dans le shell :

```
[stc:vm] Machine-spirits awakened. The Omnissiah watches over your images.

  just build    build the qcow2 image
  just run      boot the image in QEMU/KVM
```

---

## nixos

Kit complet d'opérateur NixOS : formatage, lint, secrets, inspection de déploiement,
comparaison de générations, et suivi des versions amont.

| Outil | Utilité |
|-------|---------|
| `alejandra` | Formater les fichiers `.nix` |
| `statix` | Lint pour les antipatterns |
| `deadnix` | Trouver les bindings inutilisés |
| `nh` | Appliquer les configurations NixOS (`nh os switch`) |
| `nvd` | Comparer les générations NixOS |
| `nvfetcher` | Suivre les versions amont des paquets absents de nixpkgs |
| `nix-tree` | Inspecter les tailles de fermetures |
| `nix-output-monitor` | Meilleur affichage de build |
| `sops` | Gestion des secrets |
| `serie` | Visualiseur de graphe de log git |
| `trivy` | Analyse de vulnérabilités conteneur et système de fichiers |
| `tokei` | Statistiques de code |
| `just` | Exécuteur de tâches |
| `pre-commit` | Exécuteur de hooks git |

### Suivre les paquets absents de nixpkgs

Renovate maintient à jour les images de conteneurs épinglées et les entrées de
flake. Il ne couvre pas une dérivation écrite à la main qui va chercher un
binaire ou une archive sur une page de releases amont : là, `version` et
`sha256` sont édités manuellement, dérivent en silence, et on découvre que le
paquet a des mois de retard seulement quand quelqu'un pense à regarder.

`nvfetcher` comble ce trou. Il lit un fichier TOML qui déclare, paquet par
paquet, **comment trouver la dernière version** et **où la récupérer** :

```toml
[some-cli]
src.github = "owner/repo"
fetch.url = "https://github.com/owner/repo/releases/download/$ver/some-cli-linux-x86_64"

[vendor-binary]
src.cmd = "curl -fsSL https://vendor.example/VERSION"
fetch.url = "https://downloads.vendor.example/releases/$ver/linux/x64/vendor-binary"
```

L'exécution de `nvfetcher` écrit `_sources/generated.json` avec la version et
le hash résolus, qu'une dérivation lit :

```nix
{
  lib,
  fetchurl,
}: name: let
  entry = (lib.importJSON ./_sources/generated.json).${name};
in {
  inherit (entry) version;
  src = fetchurl {inherit (entry.src) url sha256;};
}
```

Outre `src.github` et `src.cmd`, les stratégies de détection comprennent
`src.pypi`, `src.git`, et `src.manual` pour les amonts qui n'exposent aucun
point d'interrogation de version — cette dernière étant l'option honnête,
puisqu'elle inscrit que la montée de version est manuelle au lieu de laisser
croire à une automatisation qui n'existe pas.

:::caution[Le JSON généré se commite]
`nvfetcher` est un générateur qu'on lance à la main (ou depuis la CI),
**jamais** une étape de build. Le JSON généré est commité, donc l'évaluation
reste pure et reproductible : la détection de version est un acte explicite, pas
un effet de bord réseau pendant un build. Appeler `nvfetcher` depuis une
dérivation casserait cette propriété, celle que STC fait respecter partout
ailleurs.
:::

:::note[Pourquoi pas un custom manager Renovate ?]
Un `customManager` Renovate de type `regex` sait réécrire la chaîne de version,
mais pas recalculer le `sha256` qui doit changer avec elle — les regex managers
remplacent `currentValue`, `currentDigest` et le nom de la dépendance, rien
d'autre. La version bougerait, le hash non, et le build échouerait. Le seul
mécanisme Renovate capable de recalculer un hash est `postUpgradeTasks`, dont
les commandes sont filtrées par `allowedCommands`, une option réservée à
**l'auto-hébergement**. STC est branché sur l'application Renovate hébergée :
cette voie n'existe donc pas ici. D'où un second outil, délibérément.
:::
