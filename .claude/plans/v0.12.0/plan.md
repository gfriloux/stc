# Plan v0.12.0 — Garde-fous de déploiement, chantier A : relique `vmVariant`

> Process : [PROCEDURE_PLANS.md](../../../PROCEDURE_PLANS.md) → *Adding a New Relic*.
> Travail atomique, une branche, doc synchronisée dans le même commit.
>
> **Branche :** `feat/relic-vm-variant` — **Issue :** [#65](https://github.com/gfriloux/stc/issues/65)

---

## La release v0.12.0

Deux chantiers, un thème : **prouver un host avant de le pousser, et refuser
d'activer le mauvais closure.** Un plan et un ledger par chantier.

| Ordre | Chantier | Issue | Plan |
|-------|----------|-------|------|
| A | Relique `vmVariant` — booter sa propre conf en VM locale, sans secrets | [#65](https://github.com/gfriloux/stc/issues/65) | ce fichier |
| B | Relique `preSwitchChecks` — garde de hostname + diff de closure | [#68](https://github.com/gfriloux/stc/issues/68) | [`pre-switch-checks.md`](pre-switch-checks.md) |

**A avant B**, et pas l'inverse : #71 (`authorizedKeysFiles`) cite #65 nommément,
#70 (`forceImportRoot`) touche le chemin de boot de tout consommateur ZFS, et
aucune des deux ne se tranche sans un banc d'essai qui boote. A livre ce banc.

**SemVer : minor.** Deux reliques neuves, opt-in, aucune option renommée, aucun
défaut existant modifié — pré-1.0, une addition rétro-compatible est un minor.

---

## Type

Adding a relic (architectural — nouvelle relique, donc plan file).

## Objectif

Livrer `stc.relics.vmVariant` : un host construit avec STC boote en VM QEMU
locale (`nixos-rebuild build-vm`, ou
`nix build .#nixosConfigurations.<host>.config.system.build.vm`) avec ses parties
dépendantes de secrets, d'images et de pools neutralisées — **sans toucher d'un
bit la configuration de production**.

## Pourquoi

C'est la marche manquante entre « ça évalue » et « je l'ai déployé en prod » : un
vrai boot, du vrai systemd, de vraies unités, sans risque. Elle compte surtout là
où une erreur verrouille — un host joignable seulement par Tailscale, un
changement qui touche `sudo`, `users` ou `sshd`.

Les trois obstacles qui empêchent `system.build.vm` de monter sur un host STC
viennent tous de reliques STC, donc **tout consommateur de STC les rencontre et
écrirait le même contournement** :

1. **Secrets** — un host qui dérive sa clé de `/etc/ssh/ssh_host_ed25519_key`
   n'a pas de clé dans une VM neuve : l'activation des secrets échoue et tout ce
   qui en dépend tombe avec elle.
2. **Conteneurs** — les unités `oci-containers` tentent un `docker pull` ;
   `provings/docker-server.nix` documente déjà la contrainte pour les tests STC
   (« a nixosTest VM is network-isolated »).
3. **ZFS / impermanence** — `relics/nixos/impermanence.nix` fait un `zfs rollback`
   en initrd et `relics/nixos/zfs.nix` force l'import d'un pool qui n'existe pas
   dans la VM.

`provings/` n'est **pas** ça : son `default.nix` le dit (« internal QA, not a
consumer API »). Les provings testent les modules de STC ; ce qui manque, c'est
qu'un consommateur boote **sa** conf.

## Prémisses vérifiées (nixpkgs `4975466`)

| Fait | Où | Conséquence |
|------|----|-------------|
| `virtualisation.vmVariant` est un `extendModules { modules = [./qemu-vm.nix]; }` du jeu de modules du host, et `system.build.vm = config.virtualisation.vmVariant.system.build.vm` | `nixos/modules/virtualisation/build-vm.nix:13,34,57` | Écrire **uniquement** dans `virtualisation.vmVariant` ne peut pas altérer `system.build.toplevel` de la prod. C'est prouvable par égalité de `drvPath`, pas seulement affirmable. |
| `fileSystems = lib.mkIf (cfg.fileSystems != {}) (mkVMOverride cfg.fileSystems)` | `nixos/modules/virtualisation/qemu-vm.nix:1397` | Les `fileSystems` du host (datasets disko/ZFS) sont **déjà** remplacés dans la VM, à la priorité 10. Rien à faire de ce côté. |
| Ce qui ne disparaît pas tout seul : le service initrd `zfs-rollback` d'impermanence et l'épinglage `boot.kernelPackages` du relic ZFS | `relics/nixos/impermanence.nix:83-95`, `relics/nixos/zfs.nix:94-102` | D'où des bascules explicites, et non « ça se règle via `fileSystems` ». |
| Ordre de surcharge pour un utilisateur immuable : `initialHashedPassword` → `hashedPassword` → `initialPassword` → `password` → `hashedPasswordFile` ; et un `warnings` se déclenche si plusieurs de `hashedPassword`/`hashedPasswordFile`/`password` sont non nuls | `nixos/modules/config/users-groups.nix:61-63,1229-1258` | `rootPassword` doit forcer les deux variantes hachées à `null` **et** poser `password`, sinon il perd silencieusement contre un `hashedPasswordFile` de sops, ou il ajoute un warning. |
| STC n'importe **aucun** module de secrets : `sops` n'apparaît que dans des exemples de doc et dans `cogitator/home/enginseer` (le paquet CLI) | `grep -rn sops relics/ cogitator/ schematics/ provings/` | Un écrit `sops.*` dans une relique STC serait une erreur d'option inconnue chez tout consommateur qui n'importe pas sops-nix — et contredirait « STC is agnostic to the secrets backend » (CLAUDE.md). |
| Aucun site n'indexe un conteneur nommé hors de sa propre déclaration (`notify.nix:72` et `traefik.nix:123` itèrent l'attrset) ; `socket-proxy.nix:104` déclare `systemd.services."docker-network-<net>"`, qui n'est pas une unité `oci-containers` | `grep -rn 'oci-containers\.containers\."'` | `oci-containers.containers = mkForce {}` ne casse aucune évaluation, et laisse volontairement le démon docker et la création de réseau debout — la VM prouve donc que docker démarre. |

## Correction de prémisse — `disableSops` tel qu'écrit dans l'issue est rejeté

L'issue propose `disableSops = true`. Ça ne peut pas être implémenté comme tel :

- Une relique STC qui écrit `sops.*` **hardcode sops-nix**, contre la règle
  « Secrets pattern » de CLAUDE.md (STC est agnostique du backend).
- Pire, c'est une erreur d'évaluation dure : `virtualisation.vmVariant` étend le
  jeu de modules **du host**, donc l'option `sops` n'existe dans la variante VM
  que si le consommateur a importé sops-nix. Un consommateur agenix, ou sans
  secrets du tout, verrait « The option `sops' does not exist ».

Remplacement retenu, **générique en code, nommé seulement en doc** :
`skipActivationScripts` (liste de noms de scripts d'activation à vider) et
`maskUnits` (liste d'unités à désactiver). Le mécanisme ne nomme aucun backend ;
la doc donne les deux recettes (`["setupSecrets"]` pour sops-nix,
`["agenixInstall" "agenixNewGeneration"]` pour agenix).

Détail qui justifie « vider » plutôt que « supprimer la clé » : d'autres scripts
d'activation déclarent `deps = ["setupSecrets"]`. Retirer l'attribut casserait le
graphe de dépendances ; `mkForce ""` garde le nœud et en vide le corps.

## Architecture

Nouvelle relique à préoccupation unique `relics/nixos/vm-variant.nix`, enregistrée
`relics-vm-variant`. Son `config` **n'écrit que dans `virtualisation.vmVariant`** —
c'est sa seule et unique frontière, et c'est ce qui la rend inoffensive : une
relique dont le métier est « désactiver des protections » invite exactement la
mauvaise lecture, donc l'en-tête du module le dit, et le Step 2 le prouve par
`drvPath`.

Granularité **par préoccupation** et non un `enable` monolithique (question posée
par l'issue) : un consommateur peut vouloir ses conteneurs éteints mais son ZFS
debout. Chaque bascule est à `true` par défaut une fois la relique activée — la
relique est déjà opt-in, et qui demande une variante VM demande précisément que
ces trois-là s'écartent.

Mécanisme, par cible :

| Cible | Écrit | Raison |
|-------|-------|--------|
| ZFS | `stc.relics.zfs.enable = mkForce false` | Éteint l'option **que STC possède**, donc l'import forcé et l'épinglage kernel partent ensemble. Pas de chirurgie d'unité. |
| Impermanence | `stc.relics.impermanence.enable = mkForce false` | Idem : retire le service initrd `zfs-rollback` et les bind-mounts de persistance d'un coup. |
| Conteneurs | `virtualisation.oci-containers.containers = mkForce {}` | Aucun `docker pull` possible dans une VM isolée. Le backend et les unités de réseau restent — la VM prouve que le démon monte. |
| Secrets | `system.activationScripts.<n> = mkForce ""` pour chaque `skipActivationScripts` | Générique, garde le graphe `deps` intact. |
| Unités | `systemd.services.<n>.enable = false` pour chaque `maskUnits` | Pour les backends qui installent leurs secrets par unité plutôt qu'en activation. |
| Connexion | `rootPassword` → `password` + `hashedPassword`/`hashedPasswordFile` à `mkForce null` | Sans ça, une VM où personne ne peut entrer. Ordre de surcharge vérifié ci-dessus. |

Priorité : `mkForce` (50) et **non** `mkVMOverride` (10). Raison : à 10, STC
battrait silencieusement un `mkForce` du consommateur dans son propre
`virtualisation.vmVariant`. À 50, un conflit est visible, et la sortie de secours
propre est la bascule par préoccupation (`disableZfs = false`), pas une surenchère
de priorités. C'est écrit en doc.

## Global Constraints

- Namespace canonique : `stc.relics.vmVariant.*`. Aucun `mkRenamedOptionModule` —
  relique neuve, aucun ancien nom à faire survivre (Gate 3 sans objet).
- `local-vm`, `aws-ami` et `dreadnought` doivent continuer à s'évaluer, et leur
  `system.build.toplevel.drvPath` doit être **identique** avec et sans la relique
  activée. C'est la revendication centrale du chantier.
- **Aucun câblage de cogitator.** La relique reste opt-in, zéro cogitator ne
  l'active : décider à la place du consommateur qu'un mot de passe root atterrit
  dans ses builds de VM n'est pas une décision de profil. Conséquence directe :
  **pas de proving** — `provings/default.nix` les définit comme « boots a VM with
  a cogitator enabled », et aucun cogitator ne change ici. La vérification est
  faite par évaluation (Step 2), pas par nixosTest.
- Aucun secret en jeu côté STC, donc aucune option en `*File`. `rootPassword` est
  une chaîne en clair **par nature** : elle ne quitte jamais la variante VM, et la
  doc doit dire que ce n'est pas une exception au pattern `*File` mais un
  paramètre de banc d'essai.
- **Un seul commit.** CLAUDE.md impose la doc dans le même changement qu'une
  modification structurelle ; précédent des quatre dernières reliques.

## Review Focus

Modes de défaillance qu'aucune commande de vérification d'étape n'exerce, le plus
probable d'abord :

1. **VM injoignable** — un consommateur dont les clés autorisées viennent d'un
   fichier de secrets, et qui laisse `rootPassword = null`, obtient une VM où
   personne ne peut entrer : les secrets sont neutralisés, donc les clés aussi.
   Ça doit être un bloc `caution` sur la page de la relique, pas une note de bas
   de page.
2. **La VM qui surjoue sa couverture** — c'est l'avertissement de l'issue
   elle-même, et le vrai risque produit. Elle prouve le boot, systemd, les
   unités, les utilisateurs, le réseau, les shells, le pare-feu. Elle ne prouve
   **rien** sur les conteneurs, les secrets et le stockage : les trois choses
   qu'on vient d'éteindre. Une section « ce que cette VM prouve / ne prouve pas »
   dans les deux langues, sinon la relique ment.
3. **Conflit de `mkForce`** — un consommateur qui écrit déjà
   `virtualisation.vmVariant.stc.relics.zfs.enable = lib.mkForce false` entre en
   conflit de priorité avec le nôtre. Message nixpkgs lisible, mais la doc doit
   pointer la bascule (`disableZfs = false`) comme la sortie, pas un troisième
   `mkForce`.
4. **Divergence de kernel** — éteindre le relic ZFS change `boot.kernelPackages`
   dans la VM (kernel générique au lieu du LTS compatible ZFS). Le banc d'essai
   ne tourne donc pas sur le kernel de prod. Assumé et documenté : la cible est
   le câblage systemd, pas le pilote de stockage ; qui veut le kernel de prod
   pose `disableZfs = false`.
5. **`maskUnits` sur une unité inexistante** — crée une unité désactivée vide
   plutôt que d'échouer. Silencieux : une faute de frappe ne se voit pas. Assumé
   (aucun moyen de vérifier l'existence d'une unité à l'évaluation sans fausser
   le cas légitime), mais dit en doc.

## Affected Files

- [ ] `relics/nixos/vm-variant.nix` *(nouveau)*
- [ ] `relics/default.nix`
- [ ] `docs/src/content/docs/en/relics/vm-variant.md` *(nouveau)*
- [ ] `docs/src/content/docs/fr/relics/vm-variant.md` *(nouveau)*
- [ ] `docs/src/content/docs/en/relics/index.md`
- [ ] `docs/src/content/docs/fr/relics/index.md`

## Atomic Steps

### Step 1 — Implémenter la relique

**Description :** créer `relics/nixos/vm-variant.nix`.

**Interfaces :**
- Consomme : `stc.relics.zfs.enable`, `stc.relics.impermanence.enable` (STC) ;
  `virtualisation.vmVariant`, `virtualisation.oci-containers.containers`,
  `system.activationScripts`, `systemd.services`, `users.users.root.*` (amont).
- Produit : `stc.relics.vmVariant.enable` (`bool`, `false`),
  `.disableZfs` (`bool`, `true`), `.disableImpermanence` (`bool`, `true`),
  `.disableContainers` (`bool`, `true`),
  `.rootPassword` (`nullOr str`, `null`),
  `.skipActivationScripts` (`listOf str`, `[]`),
  `.maskUnits` (`listOf str`, `[]`).

**Forme :**

```nix
config = lib.mkIf cfg.enable {
  virtualisation.vmVariant = {
    stc.relics.zfs.enable = lib.mkIf cfg.disableZfs (lib.mkForce false);
    stc.relics.impermanence.enable =
      lib.mkIf cfg.disableImpermanence (lib.mkForce false);

    virtualisation.oci-containers.containers =
      lib.mkIf cfg.disableContainers (lib.mkForce {});

    system.activationScripts =
      lib.genAttrs cfg.skipActivationScripts (_: lib.mkForce "");

    systemd.services =
      lib.genAttrs cfg.maskUnits (_: {enable = false;});

    users.users.root = lib.mkIf (cfg.rootPassword != null) {
      password = cfg.rootPassword;
      hashedPassword = lib.mkForce null;
      hashedPasswordFile = lib.mkForce null;
    };
  };
};
```

En-tête du module, obligatoire et non décoratif : la relique n'écrit que dans
`virtualisation.vmVariant`, qui ne s'applique qu'au build de VM, donc elle ne
peut pas adoucir un host réel — suivi de la phrase qui dit que c'est justement
pour ça que ce mécanisme a été choisi.

**Vérification :** `nix flake check --no-write-lock-file`

### Step 2 — Enregistrer, puis prouver l'innocuité

**Description :** `relics-vm-variant = ./nixos/vm-variant.nix;` dans
`relics/default.nix`, section `--- System ---`. Puis la vérification qui porte
tout le chantier : activer la relique sur `dreadnought` (le schematic qui a ZFS,
impermanence et des conteneurs) et montrer que la prod ne bouge pas d'un bit.

**Interfaces :** consomme les options du Step 1.

**Vérification :**
```bash
nix flake check --no-write-lock-file

# Référence : drvPath du toplevel de prod, relique absente
nix eval ./schematics/dreadnought#nixosConfigurations.dreadnought.config.system.build.toplevel.drvPath --no-write-lock-file

# Même chose avec la relique activée par-dessus, via --apply sur extendModules :
nix eval --no-write-lock-file --impure --expr '
  let
    f = builtins.getFlake (toString ./schematics/dreadnought);
    base = f.nixosConfigurations.dreadnought;
    with-relic = base.extendModules {
      modules = [{stc.relics.vmVariant = {enable = true; rootPassword = "vm";};}];
    };
  in {
    prod-identique = base.config.system.build.toplevel.drvPath
                  == with-relic.config.system.build.toplevel.drvPath;
    vm-zfs       = with-relic.config.virtualisation.vmVariant.stc.relics.zfs.enable;
    vm-conteneurs = with-relic.config.virtualisation.vmVariant.virtualisation.oci-containers.containers;
    vm-rootpw    = with-relic.config.virtualisation.vmVariant.users.users.root.password;
  }'
```

Attendu : `prod-identique = true`, `vm-zfs = false`, `vm-conteneurs = {}`,
`vm-rootpw = "vm"`. Un `prod-identique = false` invalide le chantier entier et
n'est pas un détail à corriger après coup.

```bash
# Les trois schematics évaluent toujours
nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.system.build.qcow2.drvPath --no-write-lock-file
nix eval ./schematics/aws-ami#nixosConfigurations.aws-ami.config.system.build.awsImage.drvPath --no-write-lock-file
nix eval ./schematics/dreadnought#nixosConfigurations.dreadnought.config.system.build.toplevel.drvPath --no-write-lock-file
```

### Step 3 — Documentation EN + FR

**Description :** nouvelle page `relics/vm-variant.md` dans les deux langues
(sidebar autogénérée, rien à câbler dans `astro.config.mjs`), plus la ligne dans
`relics/index.md` des deux côtés.

**Contenu imposé — l'un de ces blocs manquant, l'étape n'est pas finie :**

1. L'exemple complet, avec `skipActivationScripts = ["setupSecrets"]` commenté
   « sops-nix » et la variante agenix en dessous.
2. La commande de lancement :
   `nix build .#nixosConfigurations.<host>.config.system.build.vm`
   puis `./result/bin/run-<host>-vm`.
3. Section **« Ce que cette VM prouve / ne prouve pas »** — Review Focus #2.
4. Bloc `caution` sur le verrouillage : secrets neutralisés = clés autorisées
   absentes ; sans `rootPassword`, personne n'entre (Review Focus #1).
5. La phrase sur `rootPassword` et le pattern `*File` : paramètre de banc
   d'essai, confiné au build de VM, pas une exception à la règle des secrets.
6. La sortie de secours en cas de conflit de priorité : la bascule par
   préoccupation, pas un `mkForce` de plus (Review Focus #3).
7. La divergence de kernel quand `disableZfs = true` (Review Focus #4) et le
   silence de `maskUnits` sur une faute de frappe (Review Focus #5).

**Vérification :**
```bash
just docs-parity
nix develop .#docs --command bash -c 'cd docs && npm run astro check'
grep -rn "stc\." docs/src/content/docs --include="*.md" \
  | grep -v "stc\.relics\." | grep -v "stc\.cogitator\." | grep -v "stc\.lib\." \
  | grep -v "stc\.nixosModules\." | grep -v "stc\.homeModules\."
```

**Commit message (les trois étapes, un seul commit) :**
`feat(vm-variant): boot an STC host as a local VM without secrets or images`

## Quality Gates

- [ ] `nix flake check --no-write-lock-file` passe
- [ ] Les trois schematics évaluent (`local-vm`, `aws-ami`, `dreadnought`)
- [ ] `prod-identique = true` sur `dreadnought` (Step 2)
- [ ] Pas de référence interne obsolète (`grep` filtré de CLAUDE.md)
- [ ] `just docs-parity` et `npm run astro check` verts
- [ ] `just ci` vert
- [ ] `just test` vert — aucun cogitator ne change, donc c'est une non-régression,
      pas une preuve
- [ ] Un commit atomique, vérifiable seul
