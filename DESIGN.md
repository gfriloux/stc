# DESIGN.md — Standard Template Construct

> Ce document définit l'esprit, la structure et les invariants de STC.
> Avant d'ajouter quoi que ce soit, vérifie que ça s'inscrit ici. Si ce n'est pas le cas, la réponse est non.

---

## Ce qu'est STC

STC est une **bibliothèque de flake Nix** : un ensemble de modules NixOS, modules
Home Manager, shells de développement et templates de projets réutilisables,
publiés comme un flake unique que les consommateurs importent.

Ce n'est **pas** :
- Une configuration NixOS pour une machine spécifique
- Un monorepo de dotfiles personnels
- Un overlay nixpkgs généraliste
- Un framework qui impose un système de build aux consommateurs

Les consommateurs importent STC comme input de flake et piochent ce dont ils ont
besoin. Ils possèdent leurs machines. STC possède les abstractions réutilisables.

---

## Les six piliers

STC est organisé en six répertoires racines. Chaque fichier du dépôt appartient
à exactement l'un d'eux. En cas de doute, la réponse se trouve dans les
définitions ci-dessous.

### `relics/` — Modules atomiques

Une relique est un **module NixOS ou Home Manager à préoccupation unique**. Elle
déclare des options sous `stc.*` et configure exactement une chose.

**Le seuil de la relique :** une relique doit configurer quelque chose. Si
l'intégralité du bloc `config` se résume à `home.packages = [pkgs.X]` ou
`environment.systemPackages = [pkgs.X]`, ce n'est pas une relique — c'est une
installation de paquet. Les installations de paquets appartiennent directement
dans un profil cogitator.

Les reliques sont réparties par cible :

| Chemin | Type de module |
|--------|----------------|
| `relics/nixos/` | Modules NixOS (`nixosModules.*`) |
| `relics/home/` | Modules Home Manager (`homeModules.*`) |

Les reliques sont exposées via `relics/default.nix` sous le préfixe `relics-`
(ex. `stc.nixosModules.relics-boot`).

### `cogitator/` — Profils

Un profil cogitator est une **composition de reliques** pour un cas d'usage
complet. Une seule option `enable` déverrouille une configuration complète et
opinionnée.

Les profils doivent :
- Activer plusieurs reliques (ou une relique + des paquets directs)
- N'ajouter aucune logique de configuration qui appartient à une relique
- Laisser toutes les options des reliques sous-jacentes réglables par le consommateur

**Profils constructeurs d'image (pattern sarcophagus) :** un cogitator peut
également embarquer un layout disko et un builder d'image (`system.build.qcow2`,
`system.build.awsImage`, etc.) lorsqu'il vise la production d'un artefact disque.
Dans ce cas, `disko.nixosModules.disko` est injecté dans le wrapper
`cogitator/default.nix` (pattern inputs closure), et le layout est défini
inline dans le bloc `config` à partir des options du profil.

**Profils système en cours d'exécution (pattern dreadnought) :** un cogitator
déployé sur un système déjà partitionné possède son propre layout `fileSystems`
et sa configuration `boot.loader`, dérivés de ses options (`poolName`, `ebsDisk`).
Le `hardware-configuration.nix` du consommateur n'a alors besoin que des modules
noyau spécifiques à l'instance.

Les profils sont répartis par cible :

| Chemin | Type de module |
|--------|----------------|
| `cogitator/nixos/` | Profils NixOS (`nixosModules.*`) |
| `cogitator/home/` | Profils Home Manager (`homeModules.*`) |

Les profils sont exposés via `cogitator/default.nix` sous le préfixe `cogitator-`
(ex. `stc.homeModules.cogitator-enginseer`).

### `forge/` — Artefacts de construction

La Forge produit des artefacts consommables qui ne sont pas des modules :

| Sous-répertoire | Contenu |
|-----------------|---------|
| `forge/shells/` | `devShells.*` — environnements de dev par technologie |
| `forge/templates/` | `templates.*` — projets starter pour `nix flake init` |
| `forge/layouts/` | Fonctions de layout disque disko (exposées via `stc.lib.layouts.*`) |
| `forge/purity-seals/` | Constructeurs de checks CI (exposés via `stc.lib.puritySeals.*`) |

Un shell fournit les outils pour travailler dans une technologie. Un template
fournit le squelette pour démarrer un nouveau projet dans cette technologie.
Ils vont par paire : chaque template a un shell correspondant.

### `rites/` — Bibliothèque

Fonctions Nix pures et patterns partagés. Pas d'effets de bord. Pas d'options
de module.

Tout ce qui est dans `rites/` est exposé sous `stc.lib.*`. Actuellement :
- `stc.lib.layouts.*` — constructeurs de layouts disque disko
- `stc.lib.docker.*` — helpers `mkHealthCheck`, `mkNetwork`
- `stc.lib.puritySeals.<system>.*` — constructeurs de checks CI (`nix`,
  `gitleaks`, `terraform`, `ansible`, `shell`, `markdown`) ; le code vit dans
  `forge/purity-seals/`, `rites/` l'expose (comme pour les layouts)

`rites/default.nix` déclare aussi `flake.homeModules` comme `lib.mkOption`
afin que `relics/` et `cogitator/` puissent y contribuer sans conflit.

### `schematics/` — Exemples consommateurs

Flakes autonomes qui montrent comment utiliser STC du côté consommateur.
Ils **ne font pas partie des outputs du flake** — `nix flake check` ne les
évalue pas. Ils existent comme documentation vivante.

Chaque schématique est un répertoire autonome avec son propre `flake.nix` et
son `Justfile`. Schématiques actuelles :

| Répertoire | Ce qu'il démontre |
|------------|-------------------|
| `schematics/local-vm/` | Image VM NixOS (qcow2) avec ZFS + impermanence via `cogitator-sarcophagus-kvm` |
| `schematics/aws-ami/` | AMI NixOS pour AWS avec ZFS + impermanence via `cogitator-sarcophagus-aws` |
| `schematics/dreadnought/` | Instance EC2 NixOS gérée via deploy-rs, déployée depuis une AMI aws-ami |

### `provings/` — Épreuves de la Machine

Une épreuve (proving) est un **test de comportement** : un `nixosTest` qui boote
une VM avec un cogitator activé et *vérifie* qu'il fait réellement ce qu'il
prétend (sysctl effectifs, montages `noexec`, SSH qui refuse les mots de passe…).
Là où la Forge et les Purity Seals prouvent qu'un flake *évalue*, les épreuves
prouvent qu'un système *fonctionne* — le Rite of Proving du machine spirit.

Les épreuves sont une **QA interne de STC**, pas une API consommateur. À ce titre :

- Elles sont exposées via `legacyPackages.<system>.provings.*`, que
  `nix flake check` **ignore délibérément** — elles ne font donc **pas partie du
  gate** `just ci` / Purity Seals. On les lance à la main : `just test` (chaque
  épreuve builde et exécute sa VM).
- Elles ne concernent que Linux (`x86_64-linux`) — l'attribut est vide ailleurs.
- Le builder est `pkgs.testers.runNixOSTest`.

À ne pas confondre avec `forge/purity-seals/`, qui produit des *builders de checks*
réutilisables par les flakes **consommateurs**. Les épreuves testent STC lui-même,
elles ne s'exportent pas.

---

## Le pattern inputs closure

Certains modules dépendent d'un flake upstream qui fournit son propre module
(zen-browser, catppuccin, impermanence, etc.). Ces modules ne peuvent pas être
importés directement dans un fichier `.nix` car le système de modules Nix
n'expose pas les inputs de flake.

**La règle :** envelopper le module dans une lambda dans `relics/default.nix`
ou `cogitator/default.nix` qui injecte le module upstream via `imports` :

```nix
# cogitator/default.nix
cogitator-desktop =
  { ... }:
  {
    imports = [
      inputs.zen-browser.homeModules.beta
      ./home/desktop.nix
    ];
  };
```

Le fichier interne (`desktop.nix`) ne référence jamais `inputs`. Le wrapper
dans `default.nix` est le seul endroit où l'input est manipulé.

---

## Le pattern secrets

Les reliques et profils ne stockent jamais de secrets en clair. Toute valeur
pouvant être un secret (clés API, tokens, mots de passe, emails ACME…) est
acceptée comme une **option chemin de fichier** nommée avec le suffixe `*File` :

```nix
stc.docker.notify.ntfy.topicFile = config.sops.secrets."ntfy/topic".path;
```

Le module lit le fichier à l'exécution. Le consommateur choisit son gestionnaire
de secrets (sops-nix, agenix, fichiers bruts, etc.). STC est agnostique.

---

## Conventions de nommage

Tous les namespaces d'options suivent le thème Warhammer :

| Namespace | Ce qu'il couvre |
|-----------|----------------|
| `stc.relics.<domaine>.*` | Options de relique (ex. `stc.relics.docker.traefik.*`, `stc.relics.gui.kitty.*`) |
| `stc.cogitator.<profil>.*` | Options de profil (ex. `stc.cogitator.vm.*`, `stc.cogitator.hardening.*`) |

Noms des outputs du flake :
- Reliques : `relics-<nom>` (ex. `relics-docker-traefik`)
- Profils : `cogitator-<nom>` (ex. `cogitator-enginseer`)
- Shells : nom de la technologie brut (ex. `ansible`, `terraform`)
- Templates : nom de la technologie brut (ex. `ansible`, `zensical`)

### Invariant : le code interne utilise toujours le namespace canonique

Les cogitators et les schematics **doivent toujours référencer les namespaces
canoniques** (`stc.relics.*`, `stc.cogitator.*`). Ils ne doivent jamais passer
par les aliases de dépréciation.

Les aliases (`lib.mkRenamedOptionModule`) existent uniquement pour les
**consommateurs externes** qui n'ont pas encore migré. Leur seul effet est
d'émettre un warning — le code interne de STC n'a pas à déclencher ces warnings.

> **Règle de migration :** lors de tout renommage de namespace, deux choses
> doivent se produire dans le même commit :
> 1. Ajouter `lib.mkRenamedOptionModule` pour **tous** les anciens chemins
>    (relics ET cogitators renommés).
> 2. Mettre à jour **tous** les usages internes (cogitators + schematics) vers
>    le nouveau namespace canonique.
>
> Vérification : `nix flake check` + `nix eval` de chaque schematic.

---

## Invariant : code et documentation en synchronisation

Tout changement structurel — nouveau module, option renommée, nouveau cogitator,
nouveau schematic — doit s'accompagner d'une mise à jour de la documentation dans
le **même changement**. Documentation fractionnée = documentation fausse.

> **Règle de synchronisation :** lors de tout ajout ou renommage, trois choses
> doivent se produire dans le même commit :
> 1. Modifier les fichiers `.nix` (relics, cogitators, default.nix).
> 2. Mettre à jour tous les exemples de code dans `docs/` qui référencent les
>    anciennes options.
> 3. Mettre à jour les pages d'index (`relics/index.md`, `cogitator/index.md`)
>    dans les deux langues.
>
> Vérification : `grep -rn "stc\." docs/src/content/docs` filtré sur les namespaces
> attendus doit ne renvoyer aucune référence obsolète.

---

## La porte CI

`nix flake check` doit passer en permanence. La recette `just ci` enchaîne
formatage, lint et vérification du flake. Aucun commit ne doit laisser le
flake dans un état cassé.

---

## Documentation

Le site `docs/` est bilingue : anglais (`en/`) et français (`fr/`). Chaque page
doit exister dans les deux langues. Si un nouveau module, relique ou profil est
ajouté, sa page de documentation fait partie du même changement — pas d'un
commit ultérieur.

Les pages correspondent aux modules un pour un :
- Une page par groupe de reliques (ex. toutes les reliques Docker sur une seule page)
- Une page par profil cogitator
- Une page par paire shell / template forge

---

## Ce qui n'a pas sa place dans STC

| Idée | Pourquoi pas |
|------|--------------|
| Une relique qui installe uniquement un paquet | Pas une relique — l'ajouter directement dans un profil |
| Une configuration spécifique à une machine | STC est une bibliothèque, pas une config machine |
| Un overlay nixpkgs pour des paquets upstream | Utiliser nixpkgs ou le flake upstream directement |
| Des secrets stockés en clair | Viole le pattern secrets |
| Un module qui importe directement une autre relique | Les reliques sont composées par les profils, pas entre elles |
| Un profil cogitator pour une seule relique | Un profil doit composer ≥ 2 reliques (ou une relique + paquets directs) |
