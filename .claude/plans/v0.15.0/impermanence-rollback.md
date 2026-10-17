# Plan v0.15.0 — chantier 2 : l'échec du rollback d'impermanence (#89)

> Process : [PROCEDURE_PLANS.md](../../../PROCEDURE_PLANS.md) → *Debugging —
> root cause before fixes*, *Tests — what replaces TDD*, *Adding a New Relic*.
> Ledger : [`impermanence-rollback-progress.md`](impermanence-rollback-progress.md).
>
> Chantier 2 du lot « l'impermanence prouvée ». Branche
> `fix/impermanence-rollback-failure`. **Le chantier 1
> ([`proving-sarcophagus-kvm.md`](proving-sarcophagus-kvm.md)) doit être mergé
> avant** : il construit le banc sur lequel ce correctif se mesure.

---

## Context

`relics/nixos/impermanence.nix` s'ouvre sur une promesse : *« Every boot is a
fresh start. The machine forgets. Only /persist remembers. »* Ce n'est pas une
promesse d'hygiène, c'est une promesse de sécurité — c'est elle qui garantit
qu'un attaquant qui écrit dans la racine ne survit pas au reboot.

Trois défauts, tous dans les lignes 18-24 et 87-97, cassent la promesse **en
silence**. Ils sont séparés ici parce qu'ils ont des causes différentes et des
correctifs différents.

### Défaut A — l'échec du rollback n'arrête pas le boot

```nix
services.zfs-rollback = {
  wantedBy = ["initrd.target"];            # un Wants : lien faible
  after = ["zfs-import-${cfg.poolName}.service"];
  before = ["sysroot.mount"];
  …
};
```

Aucun `Requires`, aucun `RequiredBy`, aucun `OnFailure`. Si `ExecStart` sort non
nul, `initrd.target` est atteint quand même.

**Mesuré deux fois, dans les deux sens :**

- `provings/dreadnought.nix` (v0.14.0) : dans une VM **sans pool**, l'unité
  échoue, le système monte quand même, état `degraded`. Le proving *dépend* de ce
  comportement, et le documente.
- Le spike du chantier 1, sur l'image réelle **avec** pool : l'unité réussit,
  état `running`.

Sur un hôte réel, l'échec veut dire que la racine **n'a pas été restaurée** :
l'hôte démarre avec tout ce que le boot précédent y a laissé, et le seul signe
est une unité en échec dans un journal d'initrd que personne ne lit. Pire :
l'unité `zfs-rollback` **n'a aucun fragment dans le système démarré**
(`LoadState=not-found`, mesuré et écrit dans `provings/dreadnought.nix:99-104`),
donc elle n'apparaît même pas de façon fiable dans `systemctl --failed`.

### Défaut B — le script enchaîne sur une erreur

```sh
snapshot="${poolName}/${datasetName}@blank"
if ! zfs list "$snapshot" 2>/dev/null; then
  zfs snapshot "$snapshot"
fi
zfs rollback -r "$snapshot"
```

`pkgs.writeShellScript` n'émet que `#!${runtimeShell}` — **pas de `set -e`**
(vérifié dans `pkgs/build-support/trivial-builders/default.nix:235-243`). Si
`zfs snapshot` échoue, `zfs rollback` est exécuté quand même. Et le `2>/dev/null`
sur le `zfs list` efface la seule information qui distingue « le snapshot
manque » de « le pool n'est pas importé ».

### Défaut C — un `@blank` pris sur une racine sale devient la référence

C'est le plus grave, parce que c'est le seul qui **réussit**. La création
automatique au premier boot est nécessaire — le builder d'image ne crée aucun
snapshot (mesuré au chantier 1, `grep "zfs snapshot"` dans
`make-single-disk-zfs-image.nix` : aucune occurrence). Mais la relique ne sait pas
distinguer « premier boot » de « quelqu'un a détruit `@blank` », ni de « le pool
vient d'un `zfs send` qui n'incluait pas le snapshot ». Dans ces deux derniers
cas elle re-photographie une racine déjà sale, l'unité sort 0, et **tous les boots
suivants « restaurent » un état sale**. L'impermanence est morte et rien ne le
dit.

## Type et taille

**Architectural** → plan file. Le défaut A n'a pas de correctif neutre : choisir
entre « échec fatal » et « boot quand même » est un **arbitrage
disponibilité/intégrité**, et [#69](https://github.com/gfriloux/stc/issues/69)
pousse explicitement dans l'autre sens pour un hôte headless (« `enableEmergencyMode`
… on a remote host that is indistinguishable from a dead machine »). Le correctif
ajoute une option à une relique et change un comportement de boot chez trois
cogitators.

## Prémisses mesurées (nixpkgs verrouillé, ce jour)

| Fait mesuré | Commande / source | Conséquence |
|---|---|---|
| `pkgs.writeShellScript` n'ajoute aucun `set -e` | `trivial-builders/default.nix:235-243` | Défaut B confirmé, correctif trivial. |
| Le builder d'image ne crée **aucun** snapshot | `grep` dans `make-single-disk-zfs-image.nix` | La création au premier boot est porteuse : on ne peut pas simplement la supprimer. |
| Sur l'image réelle, `vmpool/root@blank` existe après le boot 1 et le rollback **réussit** | spike du chantier 1 | Le chemin nominal est sain ; le correctif ne doit pas le casser. |
| Sans pool, l'unité échoue et le boot continue (`degraded`) | `provings/dreadnought.nix` | Défaut A confirmé. |
| `zfs-rollback` n'a **aucun fragment** dans le système démarré (`LoadState=not-found`) | `provings/dreadnought.nix:99-104` | Un échec non fatal est **invisible** à `systemctl --failed` de façon fiable → il faut un signal porté autrement. |
| L'initrd rbind-monte son `/run` sur `/sysroot/run` — « We need to propagate /run » | `systemd/initrd.nix:758-772` | **Un marqueur `/run` écrit dans l'initrd est lisible par le système démarré.** C'est le mécanisme du signal. |
| `emergency.service` et `emergency.target` sont dans la liste d'unités de l'initrd | `systemd/initrd.nix:64-65` | `OnFailure = "emergency.target"` est disponible dans l'initrd. |
| `boot.initrd.systemd.emergencyAccess` existe, défaut `null` = **aucun accès** | `systemd/initrd.nix:331-345` | Un échec fatal sur un hôte headless laisse une machine arrêtée **sans shell**. C'est l'argument de #69, et il est réel. |
| Trois cogitators consomment la relique : `sarcophagus-kvm`, `sarcophagus-aws`, `dreadnought` | `grep relics.impermanence` | Portée du changement de comportement. |
| `relics/nixos/vm-variant.nix:68-78` éteint déjà la relique dans un `vmVariant`, en disant « in a VM there is neither the pool nor the snapshot, so the service can only fail » | lecture | Le dépôt **connaît déjà** le cas VM et le traite par l'extinction. Le rendre fatal ne casse pas cette voie. |

## Décisions

### 1. Défaut B — `set -euo pipefail`, et le diagnostic n'est plus jeté

Correctif sans arbitrage. Le script devient strict, et le `2>/dev/null` du
`zfs list` disparaît au profit d'un test qui ne confond plus les deux causes :
l'absence de pool doit échouer bruyamment, l'absence de snapshot doit être le
seul cas qui mène à la création.

Concrètement : vérifier d'abord que le **dataset** existe (donc que le pool est
importé), puis seulement tester le snapshot. Un `zfs list` sur le dataset qui
échoue est une erreur fatale, pas une invitation à photographier.

### 2. Défaut A — bruyant par défaut, fatal sur demande

Nouvelle option :

```nix
stc.relics.impermanence.onRollbackFailure = lib.mkOption {
  type = lib.types.enum ["continue" "emergency"];
  default = "continue";
};
```

- `"continue"` (défaut) — le boot se poursuit comme aujourd'hui, mais l'échec
  cesse d'être silencieux (décision 3).
- `"emergency"` — l'unité porte `unitConfig.OnFailure = "emergency.target"` et
  `OnFailureJobMode = "replace-irreversibly"`. Un rollback raté **arrête le boot**.

> **Arbitré par l'utilisateur le 2026-10-17**, parmi trois propositions (fatal par
> défaut / bruyant par défaut / fatal seulement si `@blank` existait déjà).

**Ce que cet arbitrage achète.** Aucune rupture : un consommateur qui bump `stc`
sans rien changer garde exactement son comportement de boot. La correction porte
donc entièrement sur la **visibilité** — ce qui est, de fait, le vrai défaut :
l'issue ne dit pas « l'hôte démarre », elle dit « l'hôte démarre *sans
prévenir* ». Et ça laisse #69 décider seul de l'arbitrage disponibilité/intégrité
pour les profils headless, au lieu que ce chantier le préempte.

**Ce qu'il coûte, et qui doit être écrit dans la doc.** Un hôte dont le rollback
échoue démarre avec une racine sale, et c'est le défaut. L'option `"emergency"`
existe pour qui veut l'inverse, et sa documentation doit nommer son prix mesuré :
`boot.initrd.systemd.emergencyAccess` vaut `null` par défaut, donc un hôte
headless qui tombe en emergency dans l'initrd n'offre **aucun shell** — c'est une
machine à redémarrer hors bande. Qui choisit `"emergency"` sur un serveur distant
doit poser `emergencyAccess` avec.

### 3. Défaut A (suite) — un échec non fatal doit être bruyant

`"continue"` sans signal reproduirait le défaut. Le correctif s'appuie sur la
prémisse mesurée du `/run` propagé :

- le script écrit `/run/stc-impermanence-rollback-failed` quand le rollback
  échoue, et `/run/stc-impermanence-blank-created` quand il a dû créer `@blank` ;
- une unité du **système démarré**, `stc-impermanence-state.service`, lit ces
  marqueurs et échoue si le premier est là.

Ça transforme un échec invisible en une unité **chargée, nommée, en échec** dans
`systemctl --failed` — exactement la classe que `provings/dreadnought.nix` sait
épingler, et qui remonte dans n'importe quelle supervision qui regarde
`systemctl is-system-running`.

Le second marqueur n'échoue pas : il **avertit**. Créer `@blank` est normal au
premier boot et anormal ensuite, et la relique ne peut pas distinguer les deux —
donc elle le dit plutôt que de deviner (défaut C).

### 4. Défaut C — on ne tente pas de deviner le premier boot

Options écartées, et pourquoi :

- *Ne plus créer `@blank` du tout* → rien ne boote au premier démarrage (le
  builder ne le crée pas, mesuré). Fermé.
- *Faire créer `@blank` par le builder d'image* → ne couvre que les sarcophages,
  laisse `dreadnought` et tout consommateur qui apporte son propre disque. Et ça
  déplacerait de la logique de relique vers un cogitator, ce que `DESIGN.md`
  refuse.
- *Marqueur dans `/persist` pour savoir si c'est le premier boot* → `/persist`
  n'est pas monté quand l'unité tourne (elle est `before = ["sysroot.mount"]`).
  Fermé mécaniquement.

Donc : **la création reste automatique, et elle devient visible** — journal au
niveau `warning` nommant le dataset, plus le marqueur `/run` de la décision 3. La
doc gagne la phrase qui manque : si `@blank` disparaît, le boot suivant en
fabrique un nouveau depuis l'état courant, et c'est à l'opérateur de savoir que la
référence a changé.

C'est une **réduction de portée assumée** : #89 décrit le risque, ce chantier le
rend détectable sans prétendre l'empêcher. Ça va au message de clôture.

### 5. Le proving `dreadnought` : pas d'aménagement, un assert qui gagne

Le défaut `"continue"` étant celui arbitré, **le nœud `dreadnought` boote sans
rien changer** — c'est le bénéfice direct de la décision 2.

Une seule chose bouge, et dans le bon sens : le jeu d'unités en échec attendu
passe de `{"stc-grow-pool.service"}` à
`{"stc-grow-pool.service", "stc-impermanence-state.service"}`. L'échec du
rollback devient une unité **chargée du système démarré**, donc épinglable par
l'assertion existante, là où le proving devait jusqu'ici aller le chercher dans
le journal de l'initrd avec un commentaire expliquant pourquoi il n'y a pas de
fragment.

C'est la démonstration du correctif, pas un dégât collatéral : le proving qui a
trouvé le défaut est celui qui constate qu'il est réparé. Le dernier subtest
(« the impermanence rollback ran in the initrd, and failed as expected ») reste
utile — il prouve que l'unité a bien tourné — mais il n'est plus le seul témoin.

Il faut aussi **vérifier négativement** que `stc-impermanence-state.service`
n'est pas une tautologie : sous `"emergency"` sur un nœud jetable, l'unité
d'initrd doit porter `OnFailure` et ne pas le porter sous `"continue"`
(méthode de [[feedback-eval-guard-method]]).

### 6. Le proving `sarcophagus-kvm` porte le chemin nominal et le chemin fatal

Sur le banc du chantier 1, le pool existe, donc le défaut par défaut s'applique
et doit rester invisible : boot 1 et boot 2 `running`, aucun marqueur dans `/run`,
`stc-impermanence-state.service` vert.

C'est l'assertion la plus importante du chantier : **le correctif ne doit rien
casser quand tout va bien.** Le chemin fatal lui-même n'est pas mis en scène dans
une VM (détruire `@blank` entre deux boots pour voir la machine refuser de
démarrer serait un test de `systemd`, pas de STC) — ce qui est prouvé, c'est que
l'unité porte bien son `OnFailure` (`systemctl cat` dans l'initrd rendu) et que le
chemin nominal reste vert.

## Architecture

Aucune frontière de `DESIGN.md` déplacée. Tout se passe dans
`relics/nixos/impermanence.nix` : une option nouvelle sous le namespace canonique
`stc.relics.impermanence.*`, un script durci, une unité d'initrd complétée et une
unité de système démarré ajoutée par la même relique. Les trois cogitators
consommateurs ne changent pas — ils héritent du défaut.

## Global Constraints

- Namespace canonique : `stc.relics.impermanence.onRollbackFailure`. Option
  **nouvelle** → pas de `mkRenamedOptionModule`.
- Les trois schematics doivent continuer à évaluer.
- Un consommateur qui ne change rien **voit son `drvPath` bouger** (script durci,
  unité ajoutée) mais **pas son comportement de boot** — c'est ce qu'achète le
  défaut `"continue"`. Ce qu'il voit en plus : une unité en échec quand le
  rollback rate, là où il ne voyait rien. À dire dans la doc et la PR.
- Aucune option ne prend de secret → pas de suffixe `*File` en jeu.
- Doc bilingue EN+FR dans le même commit que le code.
- `just test` doit être vert sur les **huit** provings, pas seulement les deux
  touchés.

## Review Focus

- **Le chemin nominal.** Le risque numéro un n'est pas que le correctif rate son
  cas d'erreur, c'est qu'il casse le boot sain — un `set -e` mal placé, un
  `OnFailure` qui se déclenche sur un `zfs rollback` qui renvoie non-zéro pour une
  raison bénigne. Le proving du chantier 1 est le garde-fou, et il doit rester
  vert sans aucun aménagement.
- **Le nouveau bruit ne doit pas être du faux bruit.** Le défaut étant
  `"continue"`, la seule chose que le consommateur gagne est une unité en échec.
  Si elle peut échouer pour une raison étrangère au rollback — un `/run` sale, un
  marqueur laissé par un boot précédent, une course avec le montage de `/run` —
  le correctif aura remplacé un silence par un cri-au-loup, ce qui est pire. La
  condition d'échec doit être étroite et re-vérifiée au runtime.
- **`"emergency"` est un chemin que personne ne prendra par accident mais que
  quelqu'un prendra.** Sa doc doit nommer le prix mesuré (`emergencyAccess` à
  `null` = pas de shell sur un hôte headless), et le proving doit prouver que
  l'option fait quelque chose, pas seulement qu'elle évalue.
- **`OnFailureJobMode = "replace-irreversibly"` dans un initrd** : vérifier que
  ça n'interagit pas mal avec `DefaultDependencies = "no"` déjà posé sur l'unité.
- **Le marqueur `/run`** repose sur le rbind `/run` → `/sysroot/run`. Mesuré dans
  le nixpkgs verrouillé ; à re-vérifier **au runtime** dans le proving, pas sur la
  foi de la lecture du module.
- **`stc-impermanence-state.service` ne doit pas échouer sur un hôte qui n'a
  jamais eu de marqueur** (répertoire `/run` vierge) — le cas nominal est
  précisément celui-là.
- La relique est importée par trois cogitators ; vérifier qu'aucun ne repose
  implicitement sur le comportement non fatal ailleurs que dans les provings.

## Affected Files

- [ ] `relics/nixos/impermanence.nix`
- [ ] `provings/sarcophagus-kvm.nix` (chemin nominal + l'unité porte son `OnFailure`)
- [ ] `provings/dreadnought.nix` (décision 5)
- [ ] `docs/src/content/docs/en/relics/impermanence.md`
- [ ] `docs/src/content/docs/fr/relics/impermanence.md`
- [ ] `docs/src/content/docs/{en,fr}/provings/index.md` (lignes de couverture)

## Atomic Steps

### Step 1 — durcir le script (défaut B)

**Description.** `set -euo pipefail`, suppression du `2>/dev/null` masquant,
distinction dataset-absent (fatal) / snapshot-absent (création), journal
`warning` quand `@blank` est créé, écriture des deux marqueurs `/run`.

**Fichiers.** `relics/nixos/impermanence.nix`.

**Vérification.**
```bash
nix flake check --no-write-lock-file
nix build .#legacyPackages.x86_64-linux.provings.sarcophagus-kvm -L --no-write-lock-file
```
Le second est le vrai gate : il démarre l'image et le script tourne pour de bon.

**Commit.** `fix(relics): make the impermanence rollback script fail loudly`

### Step 2 — l'option et le `OnFailure` (défaut A)

**Description.** Ajouter `onRollbackFailure` (défaut `"continue"`, arbitré),
câbler `unitConfig.OnFailure` / `OnFailureJobMode` sous `"emergency"` uniquement.

**Fichiers.** `relics/nixos/impermanence.nix`.

**Vérification.**
```bash
nix flake check --no-write-lock-file
nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.system.build.qcow2.drvPath --no-write-lock-file
nix eval ./schematics/aws-ami#nixosConfigurations.aws-ami.config.system.build.awsImage.drvPath --no-write-lock-file
```
Plus une éval ciblée montrant que l'unité porte `OnFailure` au défaut et ne le
porte pas sous `"continue"` — sinon l'assert du proving serait une tautologie
(méthode de [[feedback-eval-guard-method]]).

**Commit.** `feat(relics): make a failed impermanence rollback stop the boot`

### Step 3 — le signal dans le système démarré (défaut A suite / C)

**Description.** `stc-impermanence-state.service` : lit les marqueurs `/run`,
échoue sur `…-rollback-failed`, avertit sur `…-blank-created`.

**Fichiers.** `relics/nixos/impermanence.nix`.

**Vérification.**
```bash
nix build .#legacyPackages.x86_64-linux.provings.sarcophagus-kvm -L --no-write-lock-file
```
Le chemin nominal doit laisser l'unité **verte** et `is-system-running` à
`running`.

**Commit.** `feat(relics): surface a failed impermanence rollback in the booted system`

### Step 4 — adapter les deux provings

**Description.** `provings/dreadnought.nix` : jeu d'unités en échec élargi à
`{"stc-grow-pool.service", "stc-impermanence-state.service"}`, note de portée
réécrite (l'échec est désormais visible dans le système démarré, plus seulement
dans le journal d'initrd). Aucun override sur le nœud — c'est ce qu'achète le
défaut `"continue"`. `provings/sarcophagus-kvm.nix` : chemin nominal propre
(aucun marqueur, unité verte, `running`) et preuve que `"emergency"` pose bien
`OnFailure` là où `"continue"` ne le pose pas.

**Fichiers.** `provings/dreadnought.nix`, `provings/sarcophagus-kvm.nix`.

**Vérification.**
```bash
just test
```

**Commit.** `test(provings): cover the impermanence rollback failure contract`

### Step 5 — doc bilingue

**Description.** Page de la relique (EN+FR) : la nouvelle option dans la table,
une section sur ce qui se passe quand le rollback échoue (ce qu'on voit, où, et
que le boot continue par défaut), le prix de `"emergency"` sur un hôte headless,
et la phrase manquante sur `@blank` re-créé. Lignes de couverture des provings
mises à jour.

**Fichiers.** `docs/src/content/docs/{en,fr}/relics/impermanence.md`,
`docs/src/content/docs/{en,fr}/provings/index.md`.

**Vérification.**
```bash
just docs-parity
just docs-build
```

**Commit.** `docs(relics): document the impermanence rollback failure contract`

## Quality Gates (clôture de branche)

```bash
just ci
just test                 # 8 provings
nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.system.build.qcow2.drvPath --no-write-lock-file
nix eval ./schematics/aws-ami#nixosConfigurations.aws-ami.config.system.build.awsImage.drvPath --no-write-lock-file
```

Puis la revue par **contexte neuf**, avec cette section *Review Focus* verbatim.

## Hors périmètre, explicitement

- **#69** (survivabilité headless : watchdog, `enableEmergencyMode`, `panic=1`).
  Ce chantier touche le même arbitrage et s'arrête à la relique d'impermanence.
  L'option livrée ici est le point d'accroche de #69, pas sa réponse.
- **#47** (proving `sarcophagus-aws`). Le patron existe après le chantier 1.
- Toute correction trouvée en route sur les clés SSH, si le chantier 1 montre
  qu'elles ne survivent pas : ce serait une **issue séparée**, pas un ajout à
  cette branche.
