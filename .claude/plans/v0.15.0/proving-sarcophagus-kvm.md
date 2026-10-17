# Plan v0.15.0 — chantier 1 : l'épreuve du sarcophage KVM (#46)

> Process : [PROCEDURE_PLANS.md](../../../PROCEDURE_PLANS.md) → *Tests — what
> replaces TDD* et *Adding a New Cogitator* (étape 6). Ledger :
> [`proving-sarcophagus-kvm-progress.md`](proving-sarcophagus-kvm-progress.md).
>
> Lot choisi par l'utilisateur le 2026-10-17 : **#46 + #89 — « l'impermanence
> prouvée »**. Deux plans, une branche et une PR par issue.
>
> | Chantier | Issue | Branche | Plan |
> |---|---|---|---|
> | 1 | [#46](https://github.com/gfriloux/stc/issues/46) | `test/proving-sarcophagus-kvm` | ce fichier |
> | 2 | [#89](https://github.com/gfriloux/stc/issues/89) | `fix/impermanence-rollback-failure` | [`impermanence-rollback.md`](impermanence-rollback.md) |
>
> **Ordre imposé : 1 puis 2.** `PROCEDURE_PLANS.md` → *Tests* : « A bug fix starts
> with a reproduction that fails. » Le chantier 2 est une correction de
> comportement au boot ; le banc qui l'observe est construit ici.

---

## Context

`cogitator/nixos/sarcophagus-kvm.nix` construit une image qcow2 BIOS/GRUB avec
ZFS et impermanence, et annonce que la racine est ramenée à `@blank` à chaque
boot. C'est la revendication la plus lourde du dépôt — elle porte un contrat de
sécurité, pas seulement d'hygiène — et elle n'a **aucune couverture
automatisée** : pas de `provings/sarcophagus-kvm.nix`, absent de
`provings/default.nix` et de la recette `test`.

Le palier 1 (v0.14.0) a délibérément laissé les deux sarcophages de côté au motif
que leur proving demande un « mécanisme neuf » : il faut **construire une image
et la démarrer**, là où les sept provings existants démarrent un nœud synthétisé
par le pilote de test.

Ce chantier livre ce mécanisme. Il ferme #46, et il laisse derrière lui le banc
sur lequel le chantier 2 se mesure.

## Type et taille

**Architectural** → plan file. Un proving sur un cogitator existant serait
*bounded*, mais celui-ci introduit un **patron de test nouveau dans le dépôt**
(image externe démarrée par le pilote), il contredit une note de portée publiée
dans `provings/dreadnought.nix` et dans la doc, et il répond à une question
ouverte de #89 sur les clés d'hôte SSH. Le cliquet ne descend pas.

## Prémisses mesurées (nixpkgs verrouillé, ce jour)

| Fait mesuré | Commande / source | Conséquence |
|---|---|---|
| `nixos/tests/qemu-vm-external-disk-image.nix` existe dans le nixpkgs verrouillé et démarre une image **non produite par le module qemu-vm** | lecture du fichier | C'est le patron amont. On ne l'invente pas. |
| `virtualisation.directBoot.enable`, `mountHostNixStore`, `fileSystems`, `useBootLoader`, `useEFIBoot` existent toutes | `nix eval` sur un `nixosSystem` jetable | Les quatre leviers du patron sont disponibles. |
| Avec `virtualisation.fileSystems = lib.mkForce {}` sur un nœud important `cogitator-sarcophagus-kvm` : `fileSystems."/"` vaut **`vmpool/root`** en `zfs`, et les clés sont `["/" "/boot" "/dev/shm" "/nix" "/persist" "/proc" "/tmp"]` | `nix eval` (sonde `probe2.nix`) | **Les montages ZFS du profil survivent.** La couche disque est observable — ce que le proving `dreadnought` donne pour hors de portée l'est par défaut, pas par fatalité. |
| `virtualisation.qemu.diskInterface` = `"virtio"` | même sonde | L'image attend `/dev/vda` : cohérent. |
| Le script de lancement honore `NIX_DISK_IMAGE` | `qemu-vm.nix:131,1365` | Le testScript peut substituer une surcouche COW à l'image du store. |
| `make-single-disk-zfs-image.nix` écrit `$out/nixos.root.qcow2` | `rootFilename` ligne 91 | Chemin exact pour la surcouche. |
| Le builder d'image **ne crée aucun snapshot** `@blank` | `grep "zfs snapshot"` → aucune occurrence | La création au premier boot par la relique est **porteuse**, pas décorative. Le `postCreateHook` du bloc disko du cogitator ne s'exécute pas (bloc descriptif, cf. son propre commentaire). |
| `nixos/lib/testing/nixos-test-base.nix:34` pose `system.switch.enable = mkDefault false` dans ce cas de figure, et `nixos-install` a besoin de `switch-to-configuration` | log de build, attempt 1 | Le nœud doit poser `system.switch.enable = true` — c'est ce que fait le test amont (ligne 29). |
| `qemu-vm.nix:1183` pose `boot.loader.grub.device = mkVMOverride cfg.bootLoaderDevice` (= `/dev/disk/by-id/virtio-root`), priorité 10, qui **bat le `mkForce` du cogitator** | log de build, attempt 2 | Le nœud doit poser `virtualisation.bootLoaderDevice = "/dev/vda"` — option ordinaire amont, pas une bataille de priorités. |
| L'amont `impermanence` traite les `files` par des **services** `persist-*`, pas des unités de montage : `mount-file.bash` bind-monte si la cible existe dans `/persist`, sinon il pose un **lien symbolique** (ligne 50) ; `/etc/machine-id` a une branche spéciale qui force le bind mount (lignes 42-48) | lecture de `mount-file.bash` | **Explique l'asymétrie** relevée dans `provings/dreadnought.nix:175-182`. |
| L'initrd rbind-monte son `/run` sur `/sysroot/run`, avec le commentaire amont « We need to propagate /run » | `systemd/initrd.nix:758-772` | Un marqueur écrit dans `/run` depuis l'unité de rollback **est lisible dans le système démarré**. Mécanisme retenu par le chantier 2. |

### Le spike : le patron entier, passé de bout en bout

Monté hors arbre et **vert**, avec les trois correctifs ci-dessus. Ce n'est pas
une estimation de faisabilité, c'est le banc qui tourne :

| Observation du spike | Conséquence pour le proving |
|---|---|
| `multi-user.target` atteint en **30,7 s**, `systemctl is-system-running` → **`running`** | L'image démarre réellement sous le pilote, et **rien n'échoue** — contrairement au nœud `dreadnought`, qui est `degraded` faute de pool. |
| `findmnt /` → `TARGET=/ SOURCE=vmpool/root FSTYPE=zfs` | La couche disque est observable **au runtime**, pas seulement en éval. C'est le cœur de #46. |
| `zfs list -t all` → `vmpool`, `vmpool/nix`, `vmpool/persist`, `vmpool/root`, **`vmpool/root@blank`** | Le `@blank` est créé par la relique au premier boot (le builder ne le crée pas, mesuré). |
| Journal : `Starting Rollback vmpool/root to @blank` → `Deactivated successfully` → `Finished` | Le chemin **nominal** du rollback — celui qu'aucun proving n'avait jamais observé. |
| Unités de montage actives : `-.mount`, `boot.mount`, `nix.mount`, `persist.mount`, `var-log.mount`, `var-lib-nixos.mount`, `etc-machine\x2did.mount` | Tous les montages du profil et de la relique sont là. |
| `/etc/ssh/ssh_host_{rsa,ed25519}_key[.pub]` sont **quatre liens symboliques vers `/persist/etc/ssh/…`** ; `findmnt` sur l'un d'eux → rien | La mécanique prédite par `mount-file.bash` est confirmée. **Mais la cible n'existe pas encore à ce stade** : le lien seul ne prouve pas que la clé survit. D'où la décision 3. |

> **Trois causes racines, trois correctifs, chacun lu dans la source amont avant
> d'être appliqué** — pas trois tentatives à l'aveugle sur le même symptôme. Chacun
> a fait avancer le build strictement plus loin (démarrage du builder →
> `nixos-install` → installation de GRUB → **boot vert**). La règle « trois
> correctifs ratés = l'architecture est fausse » vise les correctifs sans cause ;
> ici le troisième a abouti, et le spike ci-dessous est la preuve.

## Décisions

### 1. Le patron « image externe », et pourquoi pas le patron des sept autres

Les provings existants laissent le pilote de test synthétiser un nœud. Ça suffit
pour un profil qui configure des services, et ça ne suffit pas pour un profil
dont la revendication **est** la disposition du disque : le module qemu-vm
remplace `fileSystems` par le sien, donc un proving au patron standard
n'observerait ni le pool, ni les datasets, ni le rollback.

Le nœud sera donc :

```nix
virtualisation.directBoot.enable = false;      # démarre le GRUB de l'image
virtualisation.mountHostNixStore = false;      # le store est dans l'image
virtualisation.fileSystems = lib.mkForce {};   # n'écrase pas les montages du profil
virtualisation.bootLoaderDevice = "/dev/vda";  # prémisse mesurée
system.switch.enable = true;                   # prémisse mesurée
```

et le testScript crée une surcouche COW (`qemu-img create -b`) au-dessus de
`system.build.qcow2`, pointée par `NIX_DISK_IMAGE`. La surcouche est créée **une
fois** et survit aux redémarrages du script : c'est elle qui rend l'assertion
« écris, redémarre, vérifie » possible.

Les trois lignes `virtualisation.*` et `system.switch` sont des **concessions au
banc d'essai, pas des correctifs produit** : elles vivent dans le proving, avec
le commentaire qui dit laquelle vient de quelle mesure. C'est l'inverse de la
décision 4 de v0.14.0 (`serial-getty`), où le frottement venait d'une priorité
fautive dans la relique — ici l'amont expose les leviers prévus pour ça.

### 2. Ce que le proving assert : le contrat, pas le mécanisme

Le cœur est une séquence en deux boots, parce que c'est la seule forme qui prouve
l'impermanence :

1. **Boot 1** — le système monte. Asserts : `systemctl is-system-running` vaut
   **`running`** et non `degraded` (le spike le mesure ; c'est la différence nette
   avec le nœud `dreadnought`, et ça prouve qu'aucune unité du profil ne tombe
   quand le pool existe vraiment) ; `/`, `/nix`, `/persist` sont bien les datasets
   `vmpool/*` (`findmnt -no SOURCE,FSTYPE`) ; `vmpool/root@blank` existe après le
   premier boot alors que le builder ne l'a pas créé (prémisse mesurée) ;
   `zfs-rollback` a tourné et **réussi**. Puis on écrit deux témoins : un dans la
   racine (`/etc/stc-proving-witness`) et un sous `/persist`.
2. **`machine.shutdown()` puis `machine.start()`** sur la même surcouche.
3. **Boot 2** — le témoin de la racine a **disparu**, celui de `/persist` est
   **là**. C'est le critère d'acceptation de #46 mot pour mot, et c'est la phrase
   d'en-tête de la relique rendue vérifiable.

Pas d'assert sur le format de partition ni sur `sfdisk --dump` : le builder amont
les produit, les asserter mesurerait nixpkgs et non STC — la règle du lot v0.14.0
([[feedback-proving-assert-discrimination]]).

### 3. La question des clés SSH de #89 est tranchée ici, par la mesure

`provings/dreadnought.nix:175-182` laisse ouverte, par écrit, la question de
savoir si les quatre `/etc/ssh/ssh_host_*` sont réellement persistés — « if they
are not, every reboot of a dreadnought changes its host keys ».

Le spike a réglé la **moitié** de la question : ce sont quatre liens symboliques
vers `/persist/etc/ssh/…`, posés par `mount-file.bash`, et c'est une mécanique
légitime — une clé écrite à travers le lien atterrit dans le dataset persistant.
Ce que le spike **ne** montre pas, c'est que ça marche : au moment de la mesure
les cibles n'existaient pas encore, donc les liens étaient pendants.

Le proving tranche l'autre moitié de la seule façon qui compte pour le
consommateur : **l'empreinte de la clé d'hôte est relevée au boot 1 et comparée
au boot 2.** Comme le profil `sarcophagus-kvm` seul ne garantit pas que sshd a
généré ses clés au moment de la mesure, le boot 1 force le cas —
`ssh-keygen -A` (ou l'attente de `sshd.service`), puis relevé d'empreinte par
`ssh-keygen -lf`. Si l'empreinte change au boot 2, le lien est pendant pour de
bon et le contrat est cassé ; si elle tient, la question de `dreadnought` se
ferme.

**Les deux issues du résultat sont prévues** — c'est une mesure, donc le plan ne
présuppose pas laquelle. Si la clé change : on acte au ledger, on **ne corrige pas
dans ce chantier** (ce serait mélanger deux issues dans une branche), le proving
pose l'assertion en l'état constaté avec un commentaire qui nomme le défaut, et le
chantier 2 la retourne au vert.

### 4. Un seul nœud, et `sarcophagus-aws` reste dehors

#47 (AWS) n'est pas dans le lot. Le patron livré ici lui servira, et c'est écrit
dans l'en-tête du proving plutôt que deviné plus tard.

### 5. Le coût de `just test` augmente, et c'est dit

Ce proving construit une image disque (VM de build) **puis** démarre deux fois.
C'est de loin le plus lourd de la suite. La page de doc dit déjà pourquoi le coût
est annoncé (« a recipe too heavy to run is a gate that quietly stops being
one ») ; la ligne doit être mise à jour avec le chiffre mesuré au Step 2, pas
estimé.

## Architecture

Aucune frontière de `DESIGN.md` déplacée. `provings/` reste de la QA interne hors
`nix flake check`. Le fichier suit le contrat existant
(`{self}: { name; nodes; testScript; }`), avec un `testScript` en forme de
fonction `{nodes, ...}:` — forme déjà utilisée par le test amont, nouvelle dans ce
dépôt, parce qu'il faut lire `nodes.machine.system.build.qcow2` et
`nodes.machine.virtualisation.qemu.package`.

**Aucun fichier de `relics/` ni de `cogitator/` n'est modifié par ce chantier.**
Si une mesure en réclame un, c'est un défaut produit : il va au ledger et au
chantier 2 ou à une issue, pas dans cette branche.

## Global Constraints

- Namespaces canoniques uniquement : `stc.cogitator.sarcophagus-kvm.*`,
  `stc.relics.impermanence.*`. Aucun alias déprécié.
- Aucune option nouvelle, aucun renommage → aucun `mkRenamedOptionModule`.
- Les trois schematics doivent continuer à évaluer (`nix eval …drvPath`).
- Tout proving enregistré dans `provings/default.nix` est aussi dans la recette
  `test` du `Justfile` — sinon le vert est faux.
- Doc bilingue EN+FR dans le même commit que le code.

## Review Focus

- **Le proving peut être vert sans rien prouver.** Si `virtualisation.fileSystems
  = mkForce {}` tombait, `findmnt /` renverrait le disque du pilote de test et les
  asserts de dataset passeraient à côté. L'assert doit porter sur
  `SOURCE,FSTYPE` = `vmpool/root,zfs`, pas sur « `/` est monté ».
- **La surcouche COW doit survivre au `shutdown()`.** Si le pilote recrée l'image
  entre deux `start()`, le témoin disparaîtrait pour la mauvaise raison et le
  proving serait vert à tort. Le boot 2 doit donc aussi vérifier que le témoin de
  `/persist`, lui, **est là** — un contrôle qui tombe si l'image est réinitialisée.
- **Le `@blank` du boot 1 est pris sur la racine telle que le builder l'a laissée.**
  C'est la forme bénigne du risque que décrit #89. Si le boot 1 écrivait son témoin
  *avant* que `@blank` existe, le témoin deviendrait permanent et le boot 2 serait
  vert à tort. L'ordre (snapshot au boot 1, témoin ensuite) est donc porteur.
- **Un consommateur qui ne change rien** ne doit pas voir son `drvPath` bouger :
  aucun fichier de module n'est touché, à vérifier plutôt qu'à supposer.
- Temps de build : si le proving dépasse ce qu'une session tolère, la bonne réponse
  est de le dire dans la doc, pas de réduire les asserts.

## Affected Files

- [ ] `provings/sarcophagus-kvm.nix` *(nouveau)*
- [ ] `provings/default.nix`
- [ ] `Justfile` (recette `test`)
- [ ] `provings/dreadnought.nix` (note de portée : corriger la question laissée
      ouverte, et le « le module qemu-vm gagne contre tout » qui est vrai par
      défaut mais pas indépassable)
- [ ] `docs/src/content/docs/en/provings/index.md`
- [ ] `docs/src/content/docs/fr/provings/index.md`

## Atomic Steps

### Step 1 — le proving, avec le patron d'image externe

**Description.** Créer `provings/sarcophagus-kvm.nix` : un nœud important
`self.nixosModules.cogitator-sarcophagus-kvm`, les quatre concessions de banc
d'essai de la décision 1, et le testScript en deux boots de la décision 2 +
décision 3.

L'en-tête du fichier porte la note de portée : pourquoi ce proving ne ressemble
pas aux sept autres, quelle ligne vient de quelle mesure, et que `sarcophagus-aws`
(#47) pourra reprendre le patron.

**Fichiers.** `provings/sarcophagus-kvm.nix`.

**Vérification.**
```bash
nix build .#legacyPackages.x86_64-linux.provings.sarcophagus-kvm -L --no-write-lock-file
```
*(l'attribut n'existe qu'après le Step 2 — pendant l'itération, construire la
sonde équivalente hors arbre, comme pour le spike.)*

**Commit.** `test(provings): add sarcophagus-kvm proving booting the built qcow2`

### Step 2 — enregistrement et recette

**Description.** Une ligne dans `provings/default.nix`, une dans la recette
`test` du `Justfile`. Relever **le temps et la taille réels** de ce proving, pour
le Step 3.

**Fichiers.** `provings/default.nix`, `Justfile`.

**Vérification.**
```bash
nix flake check --no-write-lock-file
just test                 # les 8 provings, pas seulement le nouveau
```

**Commit.** `test(provings): register sarcophagus-kvm in the suite`

### Step 3 — doc bilingue

**Description.** Ligne dans la table de couverture EN et FR ; mise à jour du
paragraphe « What `just test` now costs » avec le chiffre mesuré au Step 2 ; une
section courte sur le patron d'image externe (c'est la deuxième exception du
registre après l'unfree, et elle mérite le même traitement).

**Fichiers.** `docs/src/content/docs/{en,fr}/provings/index.md`.

**Vérification.**
```bash
just docs-parity
just docs-build
```

**Commit.** `docs(provings): document the external-image proving pattern`

### Step 4 — corriger la note de portée de `dreadnought`

**Description.** Deux corrections, les deux adossées à une mesure de ce chantier :
la question ouverte sur les `ssh_host_*` (décision 3) est tranchée, et la
formulation « le module qemu-vm remplace `fileSystems` … ce qui *gagne* contre
tout ce qu'une relique peut écrire » doit dire **par défaut**, et renvoyer au
nouveau proving pour l'échappatoire.

Pas d'assert ajouté à `dreadnought` : son profil cible une AMI, le banc est
ailleurs.

**Fichiers.** `provings/dreadnought.nix`.

**Vérification.**
```bash
nix build .#legacyPackages.x86_64-linux.provings.dreadnought -L --no-write-lock-file
```

**Commit.** `docs(provings): settle the dreadnought scope note on ssh host keys`

## Quality Gates (clôture de branche)

```bash
just ci                   # fmt-check + lint + flake check + docs-parity
just test                 # 8 provings
nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.system.build.qcow2.drvPath --no-write-lock-file
nix eval ./schematics/aws-ami#nixosConfigurations.aws-ami.config.system.build.awsImage.drvPath --no-write-lock-file
```

Puis la revue par **contexte neuf** (`PROCEDURE_PLANS.md` → *Closing review*),
avec cette section *Review Focus* verbatim.
