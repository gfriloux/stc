# Plan v0.12.0 — Garde-fous de déploiement, chantier B : relique `preSwitchChecks`

> Process : [PROCEDURE_PLANS.md](../../../PROCEDURE_PLANS.md) → *Adding a New Relic*.
> Travail atomique, une branche, doc synchronisée dans le même commit.
> Chantier A d'abord : [`plan.md`](plan.md).
>
> **Branche :** `feat/relic-pre-switch-checks` — **Issue :** [#68](https://github.com/gfriloux/stc/issues/68)

---

## Type

Adding a relic (architectural — nouvelle relique, donc plan file).

## Objectif

Livrer `stc.relics.preSwitchChecks` : sur la machine cible, après la copie du
closure et **avant** son activation, deux contrôles.

1. **`hostnameGuard`** — refuser d'activer le closure du host A sur le host B.
2. **`closureDiff`** — afficher ce qui change, parce qu'un
   `nixos-rebuild --target-host` n'affiche rien.

## Pourquoi

Un consommateur multi-hosts déploie avec des commandes quasi identiques :

```
nixos-rebuild switch --flake .#clochette   --target-host guillaume@clochette.example
nixos-rebuild switch --flake .#RogueLeader --target-host guillaume@rogueleader.home
```

Inverse l'attribut de flake ou la cible, et le closure de A s'active sur B.
Rien ne l'arrête. Sur un serveur docker le résultat est immédiat : mauvais
conteneurs, mauvais routeurs Traefik, mauvais utilisateurs, mauvais secrets — et
si le changement touche `sshd` ou `sudo`, possiblement aucun retour en arrière.

`system.preSwitchChecks` est le point d'accroche prévu pour ça en amont, et STC
ne l'utilise nulle part.

## Prémisses vérifiées (nixpkgs `4975466`)

| Fait | Où | Conséquence |
|------|----|-------------|
| `system.preSwitchChecks` est un `attrsOf str` ; chaque fragment reçoit le closure entrant en `$1` et le verbe d'action en `$2` | `nixos/modules/system/activation/pre-switch-check.nix` | Le point d'accroche existe bien dans le nixpkgs verrouillé. |
| Tous les fragments sont concaténés dans **un seul** `pkgs.writeShellApplication`, et chacun tourne dans un sous-shell `( set -e … ) >&2` | idem | Deux conséquences dures : (a) `shellcheck` tourne au build, donc une variable inutilisée ou une expansion non quotée **casse le build du système**, pas le déploiement ; (b) la sortie est déjà redirigée vers stderr, donc aucun `>&2` à écrire dans nos fragments. |
| `do_pre_switch_check` lance le script avec les stdio hérités, avant l'installation du bootloader et avant l'activation, pour toutes les actions, sauf si `NIXOS_NO_CHECK=1` | `pkgs/by-name/sw/switch-to-configuration-ng/src/main.rs:233-254,1828-1836` | Un échec laisse l'ancien système debout. C'est bien un garde-fou, pas un avertissement. |
| L'action `check` ne fait **que** les contrôles puis retourne (`if *action == Action::Check { return Ok(()) }`, juste après l'appel) | idem `main.rs:1838-1840` ; enum à `main.rs:111-131` | Le proving peut exercer le garde-fou sans rien activer — ni redémarrage d'unité, ni perturbation des autres subtests. |
| Modèle amont : `system.preSwitchChecks.switchInhibitors` lit `$1`/`$2` et sort tôt sur `boot\|dry-activate` | `nixos/modules/system/activation/switchable-system.nix:76…` | La forme de nos fragments est calquée sur un fragment amont, pas inventée. |
| `nixos-enter` ne bind-monte que `/dev`, `/sys`, `/proc` (+ `resolv.conf`), s'exécute sous `unshare --uts`, et `nixos-install` y lance `/run/current-system/bin/switch-to-configuration boot` | `pkgs/by-name/ni/nixos-enter/nixos-enter.sh:15,61-65,94` ; `pkgs/by-name/ni/nixos-install/nixos-install.sh:310-322` | `/run` dans le chroot est celui de la **cible**, donc `/run/booted-system` est absent pendant une installation, alors que `/proc/sys/kernel/hostname` est celui de l'**installateur**. Le test `/run/booted-system` est donc porteur : sans lui, le garde-fou casse toute installation nixos-anywhere, qui est le chemin d'install des `schematics/`. |
| `dix 2.2.0` s'appelle `dix <OLD_PATH> <NEW_PATH>` ; binaire en cache binaire, 4,2 Mio déballés | `nix run nixpkgs#dix -- --help` | Invocation et coût de closure connus, pas supposés. |

## Correction de prémisse — `EXPECTED_HOSTNAME` ne peut pas marcher

L'issue reprend de srvos une échappatoire `EXPECTED_HOSTNAME` et en fait un
critère d'acceptation. Elle n'atteint rien quand on déploie avec
`nixos-rebuild` :

- `nixos-rebuild-ng` construit la commande via
  `/bin/sh -c 'exec /usr/bin/env -i K=V… "$@"'` avec une **liste blanche fermée**
  de trois variables : `LOCALE_ARCHIVE`, `NIXOS_NO_CHECK`,
  `NIXOS_INSTALL_BOOTLOADER` (`pkgs/by-name/ni/nixos-rebuild-ng/src/nixos_rebuild/nix.py:748-753`,
  mécanisme dans `elevate.py:56-70`).
- Et il l'enveloppe dans `systemd-run … -E LOCALE_ARCHIVE -E NIXOS_INSTALL_BOOTLOADER
  -E NIXOS_NO_CHECK` (`nix.py:40-52`) — même liste, deuxième barrière.
- Côté élévation, seule `NIXOS_NO_CHECK` est dans `Defaults env_keep`
  (`nixos/modules/system/activation/switchable-system.nix:149`).

Une variable à nous ne franchit donc ni `env -i`, ni `systemd-run -E`, ni `sudo`.
`EXPECTED_HOSTNAME` ne fonctionnerait que pour qui appelle
`switch-to-configuration` à la main — c'est-à-dire personne dans le flux que
l'issue décrit.

**Décision : aucune variable d'environnement à nous.** L'échappatoire est
`NIXOS_NO_CHECK=1`, celle d'amont, dont on vient de vérifier qu'elle traverse les
trois barrières. Coût assumé et écrit en doc : elle désactive **tous** les
contrôles pré-switch, y compris les `switchInhibitors` d'amont. C'est le prix
d'une échappatoire qui marche vraiment, contre une qui ne marche pas.

## Correction de prémisse — pas de `read` sur stdin

L'issue demande une décision explicite sur le comportement non interactif du
garde-fou. Elle est prise : **aucun prompt, jamais.**

srvos demande confirmation sur stdin. Dans le flux `nixos-rebuild --target-host`,
le script tourne sous `systemd-run --pipe --collect --service-type=exec` à travers
ssh : stdin n'est pas un terminal fiable. Et sous le `set -euo pipefail` de
`writeShellApplication`, un `read` sur un stdin vide retourne non-zéro, donc
**avorte le switch de toute façon**. Prompter, c'est donc une version
non déterministe de « avorter ». On garde le déterminisme : le garde-fou avorte,
et son message nomme les deux issues (déployer le bon attribut de flake, ou
repasser avec `NIXOS_NO_CHECK=1`).

## Architecture

Nouvelle relique à préoccupation unique `relics/nixos/pre-switch-checks.nix`,
enregistrée `relics-pre-switch-checks`. Elle n'écrit que dans
`system.preSwitchChecks.*` — deux entrées, chacune gardée par sa propre bascule.

Le hostname attendu est **gravé à l'évaluation** depuis
`config.networking.hostName`. C'est correct et non circulaire : le fragment voyage
*dans* le closure entrant, donc cette valeur est par construction le nom du host
auquel ce closure appartient. Il n'y a rien à lire dans `$1`.

Matrice de déclenchement du garde-fou, décidée :

| Situation | Garde-fou | Pourquoi |
|-----------|-----------|----------|
| action `dry-activate` | ignoré | Rien n'est activé ; avorter n'empêcherait aucun dégât. |
| action `switch`, `test`, `check` | actif | Les trois touchent le système courant. |
| action `boot` | **actif** | Divergence volontaire d'avec `switchInhibitors`, qui l'ignore : écrire l'entrée de bootloader du mauvais host est précisément la catastrophe visée, et elle ne se voit qu'au redémarrage suivant. |
| `/run/booted-system` absent | ignoré | Installation en cours (`nixos-install`/nixos-anywhere) — prémisse vérifiée ci-dessus. |
| `networking.hostName` vide | ignoré | Host nommé par DHCP : il n'y a pas de nom attendu à comparer, et c'est une configuration légitime. |

`closureDiff` est cosmétique et **ne doit jamais** faire échouer un switch : son
appel à `dix` se termine par un `|| echo "…indisponible…"`, donc le fragment sort
toujours à 0. Un seul booléen, pas d'option de paquet : `dix` et `nvd` n'ont pas
la même CLI (`dix <a> <b>` contre `nvd diff <a> <b>`), donc un
`mkPackageOption` serait un piège. Qui veut `nvd` met `closureDiff = false` et
écrit son propre `system.preSwitchChecks.<nom>` — une ligne, et c'est l'API
d'amont.

## Global Constraints

- Namespace canonique : `stc.relics.preSwitchChecks.*`. Aucun
  `mkRenamedOptionModule` — relique neuve (Gate 3 sans objet).
- Câblée dans **`cogitator/nixos/docker-server.nix` uniquement**. Pas
  `dreadnought`, pas les `sarcophagus-*` : `docker-server` est le seul cogitator
  côté serveur à avoir un proving, donc le seul endroit où la revendication est
  vérifiable dans le même changement. `dreadnought` l'activera quand son proving
  existera (#45) ; d'ici là, un consommateur dreadnought pose une ligne, et c'est
  documenté.
- Les fragments doivent passer `shellcheck` : tout est quoté, aucune variable
  assignée sans être lue, `${1-}`/`${2-}` et non `$1`/`$2` nus.
- `local-vm`, `aws-ami` et `dreadnought` doivent continuer à s'évaluer.
- Aucun secret en jeu, donc aucune option en `*File`.
- Proving obligatoire : `cogitator-docker-server` gagne une relique, donc
  `provings/docker-server.nix` doit prouver l'effet, pas seulement l'évaluation.
- **Un seul commit**, doc comprise (CLAUDE.md).

## Review Focus

Modes de défaillance qu'aucune commande de vérification d'étape n'exerce, le plus
probable d'abord :

1. **Casse de déploiement chez un consommateur qui ne change rien.** Un
   consommateur de `cogitator-docker-server` qui bump `stc` hérite du garde-fou.
   Son build ne casse pas, mais son `nixos-rebuild` **peut** se mettre à avorter
   s'il déployait déjà avec un hostname divergent — typiquement un host dont
   `networking.hostName` ne correspond pas au nom réellement posé au boot (DHCP
   qui l'écrase, `cloud-init`, nom court contre FQDN). C'est le mode de
   défaillance numéro un, il doit être un bloc `caution` avec les trois sorties :
   corriger le nom, `preSwitchChecks.hostnameGuard = false`, ou
   `NIXOS_NO_CHECK=1` pour un passage.
2. **Nom court contre FQDN.** `/proc/sys/kernel/hostname` rend ce que systemd a
   posé, qui peut être le FQDN quand `networking.domain` est défini. Une
   comparaison stricte avorterait à tort. À trancher et à vérifier dans le
   proving : comparer la partie avant le premier point des deux côtés, ou exiger
   l'égalité stricte. Le proving doit couvrir le cas `networking.domain` défini,
   sinon le garde-fou est un piège pour la moitié du parc.
3. **Build cassé par shellcheck.** Une variable inutilisée dans un fragment ne
   fait pas échouer un déploiement, elle fait échouer `nix build` du système
   entier, pour tout consommateur. C'est exercé par `nix flake check` au Step 1,
   mais seulement pour les combinaisons d'options que les schematics évaluent —
   d'où un `nix eval` explicite du script avec `closureDiff` activé et désactivé.
4. **`dix` dans le closure de tout serveur.** 4,2 Mio déballés, binaire en cache.
   Assumé, et c'est pourquoi `closureDiff` est une bascule séparée : un
   consommateur qui ne veut pas du paquet coupe le diff et garde le garde-fou.
5. **Un `closureDiff` qui avorte quand même.** Si `dix` échoue d'une manière qui
   tue le sous-shell avant le `||` (OOM, binaire absent du closure), le fragment
   sort non-zéro et bloque un déploiement pour une raison purement cosmétique.
   Le proving doit l'exercer en le faisant échouer pour de vrai, pas en
   supposant que `|| echo` suffit.

## Affected Files

- [ ] `relics/nixos/pre-switch-checks.nix` *(nouveau)*
- [ ] `relics/default.nix`
- [ ] `cogitator/nixos/docker-server.nix`
- [ ] `provings/docker-server.nix`
- [ ] `docs/src/content/docs/en/relics/pre-switch-checks.md` *(nouveau)*
- [ ] `docs/src/content/docs/fr/relics/pre-switch-checks.md` *(nouveau)*
- [ ] `docs/src/content/docs/en/relics/index.md`
- [ ] `docs/src/content/docs/fr/relics/index.md`
- [ ] `docs/src/content/docs/en/cogitator/docker-server.md`
- [ ] `docs/src/content/docs/fr/cogitator/docker-server.md`

## Atomic Steps

### Step 1 — Implémenter la relique

**Description :** créer `relics/nixos/pre-switch-checks.nix`.

**Interfaces :**
- Consomme : `config.networking.hostName` (amont), `pkgs.dix`.
- Produit : `stc.relics.preSwitchChecks.enable` (`bool`, `false`),
  `.hostnameGuard` (`bool`, `true`), `.closureDiff` (`bool`, `true`).

**Forme :**

```nix
config = lib.mkIf cfg.enable {
  system.preSwitchChecks = {
    stcHostnameGuard = lib.mkIf cfg.hostnameGuard ''
      case "''${2-}" in
        dry-activate) exit 0 ;;
      esac

      # No booted system: we are inside nixos-install / nixos-anywhere. nixos-enter
      # bind-mounts only /dev, /sys and /proc, so /run here belongs to the target
      # and is empty, while /proc/sys/kernel/hostname is the installer's. Without
      # this test the guard would abort every fresh install.
      [ -e /run/booted-system ] || exit 0

      expected=${lib.escapeShellArg config.networking.hostName}
      [ -n "$expected" ] || exit 0

      read -r running < /proc/sys/kernel/hostname
      if [ "''${running%%.*}" != "''${expected%%.*}" ]; then
        echo "stc: refusing to activate the closure of '$expected' on '$running'."
        echo "stc: deploy the right flake attribute, or re-run with NIXOS_NO_CHECK=1."
        exit 1
      fi
    '';

    stcClosureDiff = lib.mkIf cfg.closureDiff ''
      case "''${2-}" in
        dry-activate) exit 0 ;;
      esac
      [ -e /run/current-system ] || exit 0

      echo "stc: closure diff (current → incoming):"
      ${lib.getExe pkgs.dix} /run/current-system "''${1-}" \
        || echo "stc: closure diff unavailable (dix exited non-zero) — continuing."
    '';
  };
};
```

Trois points à ne pas « simplifier » plus tard, chacun commenté sur place :
- Pas de `>&2` : le wrapper amont redirige déjà le fragment entier vers stderr.
- `''${running%%.*}` des deux côtés : tranche le Review Focus #2 en comparant le
  nom court, parce que systemd peut poser le FQDN quand `networking.domain` est
  défini. Le proving le vérifie avec un `networking.domain` posé.
- `|| echo` sur `dix` : le fragment doit sortir à 0 quoi qu'il arrive.

**Vérification :**
```bash
nix flake check --no-write-lock-file

# shellcheck du script généré, dans les deux configurations d'options
nix eval --no-write-lock-file --impure --expr '
  let
    f = builtins.getFlake (toString ./schematics/dreadnought);
    mk = opts: (f.nixosConfigurations.dreadnought.extendModules {
      modules = [{stc.relics.preSwitchChecks = {enable = true;} // opts;}];
    }).config.system.preSwitchChecksScript;
  in {
    les-deux = mk {};
    diff-seul = mk {hostnameGuard = false;};
    garde-seul = mk {closureDiff = false;};
  }'
```
Les trois doivent produire un chemin de store : `writeShellApplication` lance
`shellcheck` au build, donc un chemin rendu = script propre (Review Focus #3).

### Step 2 — Enregistrer et câbler

**Description :** `relics-pre-switch-checks = ./nixos/pre-switch-checks.nix;` dans
`relics/default.nix` (section `--- System ---`) ; import +
`stc.relics.preSwitchChecks.enable = true;` dans
`cogitator/nixos/docker-server.nix`, et sa description de `mkEnableOption` dit
désormais qu'il pose aussi les contrôles pré-switch.

**Interfaces :** consomme les options du Step 1.

**Vérification :**
```bash
nix flake check --no-write-lock-file
nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.system.preSwitchChecks --apply builtins.attrNames --no-write-lock-file
nix eval ./schematics/aws-ami#nixosConfigurations.aws-ami.config.system.build.awsImage.drvPath --no-write-lock-file
nix eval ./schematics/dreadnought#nixosConfigurations.dreadnought.config.system.build.toplevel.drvPath --no-write-lock-file
```

### Step 3 — Proving

**Description :** étendre `provings/docker-server.nix`. Le nœud pose
`networking.domain` — sans ça le cas FQDN du Review Focus #2 n'est pas exercé et
le troncage `%%.*` ne prouve rien. Un commentaire le dit sur place.

Tous les asserts passent par `switch-to-configuration check`, qui ne fait que les
contrôles pré-switch puis retourne (vérifié dans `main.rs:1838-1840`) : aucune
unité n'est réactivée, donc le subtest ne perturbe pas les autres.

**Asserts, du plus faible au plus fort :**
1. **Garde de validité** : `/run/booted-system` existe dans la VM. Sans lui, le
   fragment sort tôt et tous les asserts suivants sont des tautologies. C'est le
   premier assert, pas une note.
2. `switch-to-configuration check` réussit avec le hostname correct — et le FQDN
   posé par `networking.domain` ne le fait pas échouer.
3. **Comportement** : après `hostname autre-machine`, le même
   `switch-to-configuration check` échoue, et sa sortie contient le nom attendu.
4. Le même cas avec `NIXOS_NO_CHECK=1` réussit — l'échappatoire est prouvée, pas
   supposée.
5. **Review Focus #5** : `closureDiff` ne peut pas avorter — rendre `dix`
   inopérant (`PATH` neutralisé, ou le store path du binaire masqué par un
   `mount --bind /dev/null`) et vérifier que `check` réussit toujours.

**Vérification :** `just test`

### Step 4 — Documentation EN + FR

**Description :** nouvelle page `relics/pre-switch-checks.md` dans les deux
langues, la ligne dans `relics/index.md` des deux côtés, et la page
`cogitator/docker-server.md` des deux côtés (son comportement change).

**Contenu imposé — l'un de ces blocs manquant, l'étape n'est pas finie :**

1. Bloc `caution` « ce que ça peut casser chez vous » : Review Focus #1, avec les
   trois sorties (corriger le nom, `hostnameGuard = false`, `NIXOS_NO_CHECK=1`).
2. La matrice de déclenchement (tableau *Architecture*), y compris **pourquoi
   `boot` est gardé alors qu'amont l'ignore**.
3. `NIXOS_NO_CHECK=1` présenté comme l'unique échappatoire, avec son coût : elle
   coupe aussi les contrôles d'amont. Et la raison pour laquelle il n'y a pas de
   variable à nous — `env -i` + `systemd-run -E` + `env_keep` forment une liste
   blanche fermée de trois variables.
4. La décision « aucun prompt » et son argument : sous `set -euo pipefail`, un
   `read` sur stdin vide avorte de toute façon.
5. `closureDiff` : ce qu'il ajoute au closure (`dix`, 4,2 Mio) et comment s'en
   passer en gardant le garde-fou.
6. Comment utiliser `nvd` à la place — `closureDiff = false` plus son propre
   `system.preSwitchChecks.<nom>`.

**Vérification :**
```bash
just docs-parity
nix develop .#docs --command bash -c 'cd docs && npm run astro check'
```

**Commit message (les quatre étapes, un seul commit) :**
`feat(pre-switch-checks): guard against deploying the wrong closure`

## Quality Gates

- [ ] `nix flake check --no-write-lock-file` passe
- [ ] Les trois schematics évaluent (`local-vm`, `aws-ami`, `dreadnought`)
- [ ] Le script pré-switch rend un chemin de store dans les trois combinaisons
      d'options (Step 1)
- [ ] `just test` vert — le proving de `docker-server` inclus
- [ ] Pas de référence interne obsolète (`grep` filtré de CLAUDE.md)
- [ ] `just docs-parity` et `npm run astro check` verts
- [ ] `just ci` vert
- [ ] Un commit atomique, vérifiable seul
