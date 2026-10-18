# Plan v0.16.0 — chantier 1 : l'épreuve du sarcophage AWS (#47)

> Process : [PROCEDURE_PLANS.md](../../../PROCEDURE_PLANS.md) → *Tests — what
> replaces TDD* et *Adding a New Cogitator* (étape 6). Ledger :
> [`proving-sarcophagus-aws-progress.md`](proving-sarcophagus-aws-progress.md).
>
> Lot choisi par l'utilisateur le 2026-10-18 : **#47 + #83 + #50 — « les épreuves,
> palier 2 »**. Deux plans, une branche et une PR par issue.
>
> | Chantier | Issue | Branche | Plan |
> |---|---|---|---|
> | 1 | [#47](https://github.com/gfriloux/stc/issues/47) | `test/proving-sarcophagus-aws` | ce fichier |
> | 2 | [#83](https://github.com/gfriloux/stc/issues/83) | `test/proving-enginseer` | [`proving-home-manager.md`](proving-home-manager.md) |
> | 3 | [#50](https://github.com/gfriloux/stc/issues/50) | `test/proving-home-desktop` | [`proving-home-manager.md`](proving-home-manager.md) |
>
> **Ordre : 1, puis 2, puis 3.** Le chantier 1 est indépendant (il réutilise un
> patron livré en v0.15.0) ; les chantiers 2 et 3 partagent un mécanisme neuf, et
> 3 consomme une assertion que 2 établit. Détail dans l'autre plan.
>
> **À la fin du lot, chaque cogitator du dépôt a son épreuve** — la règle de
> `CLAUDE.md` étape 6 tiendra sur l'existant et pas seulement sur le neuf.

---

## Maintenance Plan: l'épreuve du sarcophage AWS

**Type :** ajout d'une épreuve (`provings/`) sur un cogitator existant.

**Goal :** `provings/sarcophagus-aws.nix` construit l'image raw que
`cogitator-sarcophagus-aws` existe pour produire, la démarre, et prouve la seule
revendication que cette image porte et que les huit autres épreuves ne peuvent
pas atteindre : **la croissance du pool ZFS sur un disque plus grand que
l'image**.

**Why :** `cogitator/nixos/sarcophagus-aws.nix` est, avec les deux cogitators
Home Manager, le dernier profil du dépôt sans épreuve. Le palier 1 (v0.14.0)
avait écarté les deux sarcophages faute de mécanisme ; v0.15.0 a livré ce
mécanisme pour le KVM, et l'en-tête de `provings/sarcophagus-kvm.nix` dit
nommément que #47 peut le réutiliser tel quel. Le coût d'entrée est donc payé.

**Architecture :** patron « image externe » — le nœud déclare l'image, le pilote
de test démarre *cette image* au lieu de synthétiser une racine. Zéro fichier de
`relics/` ou de `cogitator/` ne change : ce chantier n'est pas sur la frontière
DESIGN.md, il observe un pilier existant (`provings/`, 6ᵉ pilier sanctionné).

## Type et taille

**Architectural** → plan file, bien que le patron existe désormais. Trois raisons
qui tiennent le cliquet en haut :

1. L'épreuve doit **déplacer une option du cogitator** (`ebsDisk`) pour que le
   chemin de croissance EBS soit atteignable sur un disque virtio — ce n'est pas
   un détail de câblage, c'est la décision qui fait la différence entre une
   épreuve verte et une épreuve qui prouve quelque chose (décision 2).
2. Elle doit **décider ce qu'elle ne réasserte pas**. L'impermanence et le
   rollback sont déjà prouvés par `sarcophagus-kvm` sur la *même* relique ; les
   répéter ici doublerait le poste le plus lourd de `just test` pour mesurer deux
   fois le même code (décision 3).
3. Elle touche les notes de portée publiées dans `docs/*/provings/index.md`, qui
   annoncent explicitement « This is the pattern #47 should reuse » et « The AWS
   serial console has no coverage at all ».

## Prémisses mesurées (nixpkgs verrouillé, 2026-10-18)

| Fait mesuré | Commande / source | Conséquence |
|---|---|---|
| `make-single-disk-zfs-image.nix` mappe `raw → ".img"` et écrit `$out/nixos.root${suffix}` | lecture du fichier, lignes 82-91 (`filenameSuffix`, `rootFilename`) | La surcouche COW se prend sur **`${awsImage}/nixos.root.img`**, pas `.qcow2` — et `qemu-img` doit recevoir `-F raw`, pas `-F qcow2`. C'est la seule ligne du patron KVM qui change. |
| Le patron « image externe » est livré et documenté : les cinq concessions de banc (`directBoot.enable=false`, `mountHostNixStore=false`, `fileSystems = mkForce {}`, `bootLoaderDevice="/dev/vda"`, `system.switch.enable=true`) | `provings/sarcophagus-kvm.nix`, en-tête + nœud | Réutilisable **tel quel**. L'en-tête le dit : les cinq lignes sont commentées une par une « c'est la raison pour laquelle #47 peut le réutiliser ». |
| `relics/nixos/aws.nix` : `stc-grow-pool` lance `growpart /dev/${ebsDisk} ${ebsPartition}` puis `zpool online -e ${poolName} /dev/${ebsDisk}${partSep}${ebsPartition}` ; il tolère `rc=1` (rien à agrandir) et échoue à `rc≥2` | lecture de la relique | Avec le défaut `ebsDisk = "nvme0n1"`, **le périphérique n'existe pas** dans une VM virtio → `rc≥2` → l'unité échoue → système `degraded`. D'où la décision 2. |
| `partSep` = `"p"` si `ebsDisk` finit par un chiffre, `""` sinon (`builtins.match ".*[0-9]"`) | lecture de la relique | `"vda"` → `partSep = ""` → `/dev/vda3`. Cohérent avec la disposition 3 partitions, et `ebsPartition = 3` est déjà le défaut. **Poser `ebsDisk = "vda"` exerce la branche sans `p`**, celle des instances Xen. |
| Le cogitator expose `ebsDisk` / `ebsPartition` et les passe à la relique (`inherit (cfg) ebsDisk ebsPartition`) | `cogitator/nixos/sarcophagus-aws.nix` | Poser l'option sur le nœud prouve aussi le **filetage cogitator → relique**, exactement comme `impermanence.extraDirectories` le fait dans l'épreuve KVM. |
| `systemd.services."serial-getty@ttyS0".enable = lib.mkDefault true` depuis le chantier #45 | `relics/nixos/aws.nix`, commentaire de la ligne | **Plus de conflit dur** avec l'instrumentation nixosTest : c'était le blocage qui rendait tout proving de ce profil impossible. Le getty reste éteint sous le pilote (l'instrumentation gagne un contest ordinaire), donc la console série reste non couverte. |
| `console=ttyS0,115200n8` est posé par le socle de test sur un nœud **nu** | mesuré au chantier #45 (v0.14.0), noté dans `docs/*/provings/index.md` | **Non discriminant.** Seuls `nvme_core.io_timeout=4294967295` et `random.trust_cpu=on` distinguent la relique d'un défaut. |
| Le pool, les datasets et les montages du profil sont observables sous le patron image externe (`findmnt /` → `vmpool/root`, `zfs`) | épreuve `sarcophagus-kvm`, verte | La couche disque est assertable ici aussi — la note de portée de `dreadnought` ne s'applique qu'au patron standard. |
| `cogitator/nixos/sarcophagus-aws.nix` déclare `/boot` = `/dev/disk/by-label/ESP` en `vfat` (`mkForce`), et GRUB BIOS sur `/dev/vda` | lecture du cogitator | Assertable par `findmnt`. ~~**Discriminant vis-à-vis du KVM**~~ — **prémisse fausse, corrigée au banc** : `cogitator/nixos/sarcophagus-kvm.nix:114` déclare un `/boot` identique au byte. L'assert garde sa place parce que les deux cogitators portent chacun leur copie de la déclaration, pas parce que l'AWS serait différent. |
| `blacklistedKernelModules = ["xen_fbfront"]`, `kernelModules = ["ena" "xen_netfront"]`, `services.udev.packages = [pkgs.amazon-ec2-utils]`, `boot.zfs.devNodes = "/dev"` | lecture de la relique | Quatre candidats d'assertion propres à AWS, dont aucun n'est posé par un nœud nu. Leur caractère discriminant est **à vérifier un par un** avant écriture (gate PF-3). |

### Ce qui n'est pas encore mesuré, et qui l'est au banc

Ces trois points ne changent pas la *forme* du plan, mais chacun peut changer un
assert. Aucun ne sera écrit sans mesure — c'est le gate PF-3.

| Inconnue | Comment on la lève | Issue si elle tombe mal |
|---|---|---|
| `growpart` accepte-t-il d'agrandir la partition 3 d'une GPT dont l'en-tête de secours est à l'ancienne fin de disque ? | lancer le banc et lire `journalctl -u stc-grow-pool` | Si `growpart` refuse, l'assert de croissance devient « l'unité a tourné et n'a pas échoué » et la **cause** est consignée au ledger. Pas de contournement silencieux. |
| `services.timesyncd` est-il allumé dans l'image (le socle de test l'éteint sur un nœud nu — note de portée `dreadnought`) ? | `systemctl is-enabled systemd-timesyncd` + présence de `/etc/systemd/timesyncd.conf` | Si éteint, `networking.timeServers = ["169.254.169.123"]` reste **non couvert** et la note de portée de la doc le dit, comme elle le dit déjà pour `dreadnought`. |
| `ena` / `xen_netfront` se chargent-ils sans le matériel correspondant ? | `lsmod` sur le banc | Si non chargés, l'assert porte sur `modinfo` (le module est dans l'arbre) et non sur `lsmod`, ou il est abandonné avec sa raison écrite. |

## Décisions

### 1. Patron « image externe », une seule ligne de différence avec le KVM

L'épreuve suit `provings/sarcophagus-kvm.nix` : surcouche COW sur l'image du
store, `NIX_DISK_IMAGE` pointé dessus, cinq concessions de banc sur le nœud. La
seule différence est le format : `nixos.root.img` et `-F raw`.

Ce qui est délibérément **copié et non factorisé** : les cinq lignes de
concession et le bloc `qemu-img`. Une fonction partagée entre deux épreuves
cacherait précisément les lignes que l'en-tête du KVM documente une par une, et
une épreuve dont on ne peut pas lire le banc dans son propre fichier est une
épreuve qu'on n'ose plus modifier. Deux occurrences ne font pas une
abstraction ; si un troisième sarcophage arrive, on factorisera avec trois cas
sous les yeux.

### 2. `ebsDisk = "vda"` sur le nœud — le cœur de l'épreuve

**Le défaut `nvme0n1` rendrait l'épreuve rouge pour une raison de banc**, pas de
produit : `growpart /dev/nvme0n1 3` ne trouve pas le périphérique, sort avec
`rc≥2`, et `stc-grow-pool` échoue. On aurait alors le choix entre asserter
« l'unité échoue » (qui ne mesure rien de STC) ou accepter un système `degraded`
(qui masque toute régression future).

Poser `stc.cogitator.sarcophagus-aws.ebsDisk = "vda"` fait trois choses d'un coup :

1. Le périphérique correspond au disque virtio du banc, donc **le chemin de
   croissance s'exécute vraiment** — `growpart` sur une vraie table de
   partitions, puis `zpool online -e` sur un vrai pool.
2. Ça prouve le **filetage de l'option** du cogitator jusqu'à la relique, au lieu
   de ne prouver que la valeur par défaut de la relique.
3. `"vda"` ne finit pas par un chiffre, donc ça exerce la branche `partSep = ""`
   — celle des instances Xen (`xvda`), qui est l'autre moitié d'un calcul dont
   l'épreuve `dreadnought` ne voit que la chaîne rendue.

Et ça rend l'assertion forte atteignable : **`systemctl is-system-running` doit
rendre `running`**, pas `degraded`. Sur ce profil, cette seule ligne attrape
toute régression qui ferait échouer une unité au boot.

### 3. La surcouche est plus grande que l'image, et c'est l'assertion phare

`qemu-img create -f qcow2 -b <image> -F raw <overlay> 8G` donne un disque virtuel
de 8 GiB dont le début est l'image. C'est exactement la situation d'un EC2 lancé
sur un volume EBS plus grand que l'AMI — **la raison d'être de
`stc-grow-pool`**.

> **Correction post-livraison (revue de clôture, 2026-10-18).** Ce paragraphe
> disait « sur une image de 4096 MiB […] dont les 4 premiers GiB sont l'image »
> et justifiait le seuil par « au-dessus de la taille de l'image ». **Les deux
> étaient faux**, et c'est la revue par contexte neuf qui l'a attrapé.
> `rootSize = 4096` est la taille de la **partition ZFS**, pas de l'image :
> l'amont crée le fichier à `bootSize + rootSize` avec `bootSize ? 1024`, donc
> **5120 MiB**. Mesuré sur l'artefact : fichier de 5368709120 octets (5 GiB
> pile) et p3 de 8386560 secteurs (3,999 GiB). Le seuil de 5 GiB tombait donc
> *exactement sur* la taille de l'image, sans aucune marge de ce côté.

L'assert : après le boot, `zpool list -Hpo size vmpool` doit dépasser 5 GiB. Le
seuil est adossé au **pool** — la grandeur effectivement lue — et non au fichier
image : mesuré, le pool passe des 3,999 GiB de p3 à 6,75 GiB, donc 5 GiB est à
~1 GiB au-dessus de l'un et ~1,75 GiB en dessous de l'autre. Sans la relique il
n'y a aucune unité de croissance et le pool resterait à ~4 GiB : l'assert
**discrimine par construction**.

C'est la seule revendication du dépôt que ni `dreadnought` (qui ne voit que la
chaîne du script) ni `sarcophagus-kvm` (dont le disque fait la taille de l'image)
ne peuvent atteindre.

### 4. Un seul boot, et ce qui n'est pas réasserté

L'épreuve KVM démarre deux fois pour prouver le rollback `@blank`. Celle-ci
démarre **une fois**.

L'impermanence, le rollback, la création de `@blank` et la survie des clés
d'hôte SSH sont produits par `relics/nixos/impermanence.nix` — la *même* relique,
déjà prouvée par `sarcophagus-kvm` sur un vrai pool, dans les deux sens, avec la
mécanique expliquée. Les répéter ici ajouterait ~60 s au poste déjà le plus
lourd de `just test` pour mesurer deux fois le même code. Un gate trop lourd
pour être lancé cesse d'être un gate — c'est écrit dans la doc des provings, et
cette décision l'applique.

Ce que l'épreuve asserte est donc **ce qui est propre à AWS** : la croissance du
pool, la disposition BIOS/GRUB + ESP par label, les deux paramètres noyau
discriminants, la blacklist `xen_fbfront`, les règles udev `amazon-ec2-utils`, et
`boot.zfs.devNodes`.

Non asserté, avec la raison écrite dans l'en-tête du fichier :

- **La console série.** Le getty reste éteint sous le pilote (l'instrumentation
  claime `ttyS0`), et `console=ttyS0,115200n8` est posé par le socle. Inchangé
  depuis `dreadnought`.
- **La disposition des partitions** (bios_grub + ESP + ZFS) : produite par
  `make-single-disk-zfs-image.nix`, donc l'asserter mesurerait nixpkgs.
- **Le bloc `disko.devices` du cogitator**, qui est descriptif et dont le propre
  commentaire dit qu'il ne partitionne pas l'image.
- **Le rollback et la persistance** : voir ci-dessus.

### 5. Aucun fichier de `relics/` ni de `cogitator/` ne change

C'est une contrainte, pas une prédiction. Si le banc révèle un défaut produit —
le motif a payé trois fois en v0.14.0/v0.15.0 (`aws.nix`, `plasma6.nix`,
l'impermanence) — il est consigné au ledger et **traité hors de ce chantier**,
soit par une issue, soit par un commit séparé annoncé. Ce qu'on ne fait pas :
corriger la relique en silence dans le commit de l'épreuve, où la revue de
clôture ne le verra pas.

## Global Constraints

- L'épreuve vit sous `legacyPackages.<system>.provings.sarcophagus-aws` —
  **hors** du gate `nix flake check` / `just ci`, comme les huit autres.
- Elle est construite depuis le `pkgs` ordinaire de flake-parts. **Pas**
  `pkgs-unfree` : aucun paquet unfree dans ce profil (le seul cas du dépôt reste
  `gaming`).
- Signature du fichier : `{self}: { name; nodes; testScript; }` — identique aux
  huit autres. Pas besoin d'`inputs` ici (le cogitator injecte disko et
  impermanence lui-même via `cogitator/default.nix`).
- Les trois schematics continuent d'évaluer, `schematics/aws-ami` en premier
  (c'est le consommateur direct de ce cogitator).
- Zéro option nouvelle, zéro namespace touché, donc aucun
  `mkRenamedOptionModule`.
- Aucun secret : rien dans ce chantier ne lit de fichier d'identifiants.

## Review Focus

Modes de défaillance que les commandes de vérification des steps n'exercent pas,
le plus probable d'abord :

- **Une épreuve verte pour une raison de banc.** Le risque principal du patron
  image externe : l'assert de croissance pourrait passer parce que `growpart` a
  agrandi quelque chose d'autre, ou que le pool était déjà à 8 GiB. Mitigation :
  relever `zpool list -Hpo size` **avant** d'avoir rien à agrandir est
  impossible en un seul boot, donc l'assert est encadré par deux faits lus au
  même endroit — `stc-grow-pool` a réussi *et* la taille dépasse le seuil — et le
  journal de l'unité est lu, pas seulement son code de retour.
- **Un consommateur qui ne change rien.** Zéro fichier de `relics/` ou
  `cogitator/` ne bouge, donc l'impact aval est nul par construction. Vérifié par
  l'identité du `drvPath` de `schematics/aws-ami` avant/après le chantier — c'est
  la mesure, pas le raisonnement, qui le dit.
- **Le poids de `just test`.** Le profil construit une image disque dans sa
  propre VM avant que le test démarre. L'épreuve KVM coûte déjà ~66 s de script
  plus la construction d'image ; celle-ci ajoute un second builder d'image. Le
  chiffre réel est mesuré et écrit dans la doc (step 2), pas estimé.
- **Non-déterminisme du `running`.** L'épreuve `dreadnought` a dû filtrer sur la
  colonne `loaded` de systemd parce qu'une unité d'initrd sans fragment
  apparaissait ou non selon les runs. Ici le pool existe donc le rollback
  réussit ; si `is-system-running` s'avère instable, la cause est cherchée avant
  tout assouplissement de l'assert.

## Affected Files

- [ ] `provings/sarcophagus-aws.nix` *(nouveau)*
- [ ] `provings/default.nix` — une ligne de registre
- [ ] `Justfile` — une ligne dans la recette `test`
- [ ] `docs/src/content/docs/en/provings/index.md`
- [ ] `docs/src/content/docs/fr/provings/index.md`

**Ne doivent pas changer :** tout `relics/**`, tout `cogitator/**`, tout
`schematics/**`. Vérifié par `git diff --name-only` avant chaque commit.

## Atomic Steps

### Step 1 : l'épreuve, et son enregistrement

**Description :** écrire `provings/sarcophagus-aws.nix` (patron image externe,
un nœud, un boot), l'enregistrer dans `provings/default.nix` et l'ajouter à la
recette `test` du `Justfile`.

**Pourquoi les trois fichiers dans un seul commit :** l'épreuve n'est
*vérifiable* qu'une fois l'attribut `legacyPackages….provings.sarcophagus-aws`
présent. C'est le ruling pris et appliqué en v0.15.0 (step 1+2 fusionnés), avec
le précédent du chantier 3-B. Une recette `test` qui ne construit pas une épreuve
enregistrée est un faux vert — la doc le dit déjà en gras.

**Files changed :**
- `provings/sarcophagus-aws.nix`
- `provings/default.nix`
- `Justfile`

**Contenu du nœud** (valeurs exactes, pas de « à adapter ») :

```nix
nodes.machine = {lib, ...}: {
  imports = [self.nixosModules.cogitator-sarcophagus-aws];

  stc.cogitator.sarcophagus-aws = {
    enable = true;
    # Décision 2 : le disque du banc est virtio. Déplacer l'option prouve son
    # filetage jusqu'à la relique et exerce la branche partSep = "" (Xen).
    ebsDisk = "vda";
    impermanence.extraDirectories = ["/var/lib/stc-proving"];
  };

  networking.hostId = "deadbeef";

  # Les cinq concessions de banc — voir provings/sarcophagus-kvm.nix.
  virtualisation.directBoot.enable = false;
  virtualisation.mountHostNixStore = false;
  virtualisation.fileSystems = lib.mkForce {};
  virtualisation.bootLoaderDevice = "/dev/vda";
  system.switch.enable = true;
};
```

**Surcouche COW** (la seule différence avec le KVM, plus la taille) :

```python
subprocess.run([
    "${nodes.machine.virtualisation.qemu.package}/bin/qemu-img",
    "create", "-f", "qcow2",
    "-b", "${nodes.machine.system.build.awsImage}/nixos.root.img",
    "-F", "raw",
    overlay.name,
    "8G",          # décision 3 : plus grand que le fichier image (5120 MiB)
], check=True)
```

**Asserts prévus** (chacun conditionné au gate PF-3 — un assert non discriminant
est supprimé, pas affaibli) :

| Subtest | Assertion | Ce qu'il discrimine |
|---|---|---|
| l'image démarre proprement | `systemctl is-system-running` → `running` | toute unité du profil qui échoue au boot |
| les datasets du profil sont montés | `findmnt -no SOURCE,FSTYPE` sur `/`, `/nix`, `/persist` → `vmpool/*` + `zfs` | le bloc `fileSystems` du cogitator, et non le disque du pilote |
| `/boot` est l'ESP de la disposition BIOS | `findmnt -no SOURCE,FSTYPE /boot` → `/dev/disk/by-label/ESP` + `vfat` | propre à l'AMI (`mkForce` du cogitator), distinct du KVM |
| **le pool a grandi** | `stc-grow-pool` a `Finished` dans son journal **et** `zpool list -Hpo size vmpool` > `5*1024**3` | la relique AWS — sans elle, aucune unité de croissance n'existe |
| les deux paramètres noyau discriminants | `nvme_core.io_timeout=4294967295` et `random.trust_cpu=on` dans `/proc/cmdline` | mesurés discriminants au chantier #45 |
| `xen_fbfront` est blacklisté | `modprobe --showconfig` (normaliser tirets/underscores des deux côtés) | la relique ; gotcha connu depuis 3-B |
| les règles udev EC2 sont posées | règle issue d'`amazon-ec2-utils` présente dans l'arbre de règles | `services.udev.packages` de la relique |

**Interfaces :**
- Consomme : `self.nixosModules.cogitator-sarcophagus-aws` (enregistré dans
  `cogitator/default.nix`, injecte disko + impermanence) ;
  `stc.cogitator.sarcophagus-aws.{enable,ebsDisk,ebsPartition,poolName,impermanence.extraDirectories}` ;
  `system.build.awsImage`.
- Produit : `legacyPackages.<system>.provings.sarcophagus-aws` (dérivation de
  test) ; la ligne `nix build .#legacyPackages.x86_64-linux.provings.sarcophagus-aws`
  de la recette `test`.

**Verification command(s) :**
```bash
nix build .#legacyPackages.x86_64-linux.provings.sarcophagus-aws -L --no-write-lock-file
just test
git diff --name-only | grep -E '^(relics|cogitator|schematics)/' && echo "VIOLATION" || echo "ok"
```

**Commit message :** `test(provings): boot the AWS image and prove the EBS pool grows`

---

### Step 2 : la doc des provings, EN + FR

**Description :** quatre endroits précis de `docs/*/provings/index.md`.

**Files changed :**
- `docs/src/content/docs/en/provings/index.md`
- `docs/src/content/docs/fr/provings/index.md`

**Ce qui change, point par point :**

1. **Table de couverture** — une ligne `sarcophagus-aws`, décrivant la croissance
   du pool comme la revendication centrale, pas l'image comme un artefact.
2. **Paragraphe « What `just test` now costs »** — passe de huit épreuves/onze
   boots à **neuf/douze**, avec le temps réel mesuré au step 1 (pas estimé), et
   la mention que deux épreuves construisent désormais une image disque.
3. **Section « Booting a real image — the external-image pattern »** — la
   dernière phrase, « This is the pattern #47 (`sarcophagus-aws`) should reuse »,
   devient le constat qu'il le réutilise, avec **la seule différence** nommée
   (`nixos.root.img` / `-F raw`) et la raison pour laquelle les cinq lignes sont
   copiées plutôt que factorisées (décision 1).
4. **Note de portée AWS** — la section `dreadnought` dit « The AWS serial console
   has no coverage at all ». Elle reste vraie et doit le dire à nouveau pour
   cette épreuve, avec ce qui a *changé* : la croissance du pool, la disposition
   BIOS/ESP et les datasets passent de non couverts à couverts, et la console
   série reste le trou admis.

**Interfaces :**
- Consomme : le nom d'attribut `provings.sarcophagus-aws` et les asserts
  effectivement retenus au step 1 (la table décrit ce qui est écrit, jamais ce
  qui était prévu).
- Produit : rien qu'un step ultérieur ne lise.

**Verification command(s) :**
```bash
just docs-parity
nix develop .#docs --command npm run astro check
just ci
```

**Commit message :** `docs(provings): record the AWS image proving and what it covers`

## Quality Gates

- [ ] `nix build .#legacyPackages.x86_64-linux.provings.sarcophagus-aws -L --no-write-lock-file`
- [ ] `just test` — les neuf épreuves, vert
- [ ] `just ci` (alejandra + statix + deadnix + `nix flake check`)
- [ ] `nix eval ./schematics/aws-ami#nixosConfigurations.aws-ami.config.system.build.awsImage.drvPath --no-write-lock-file`
      — **et ce `drvPath` est identique avant/après le chantier** (preuve d'impact nul)
- [ ] `nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.system.build.qcow2.drvPath --no-write-lock-file`
- [ ] `nix eval ./schematics/dreadnought#…` (même forme que les deux autres)
- [ ] `just docs-parity`
- [ ] `nix develop .#docs --command npm run astro check`
- [ ] `git diff --name-only` ne contient **aucun** chemin sous `relics/`,
      `cogitator/` ou `schematics/`
- [ ] Revue de clôture par **contexte neuf** avant la PR (c'est le gate qui a le
      mieux payé sur les deux lots précédents : 5 Important dont 3 invisibles de
      l'intérieur)

## Pre-flight scan

À lire avant le step 1, une ligne de ledger chacun :

- **PF-1** — Step 1 produit `provings.sarcophagus-aws` ; step 2 consomme ce nom
  exact dans la table de couverture et dans la recette citée. Vérifier que les
  deux l'écrivent pareil (`sarcophagus-aws`, pas `sarcophagus_aws` ni `aws`).
- **PF-2** — Les options consommées par le nœud existent avec l'orthographe
  écrite ci-dessus : `stc.cogitator.sarcophagus-aws.ebsDisk` (et non
  `stc.relics.aws.ebsDisk`, qui existe aussi et que le nœud ne doit **pas**
  poser, sinon le filetage n'est plus ce qui est prouvé).
- **PF-3** — **Avant d'écrire chaque assert**, le mesurer sur un nœud nu et, là
  où ça a du sens, sur un nœud portant le module amont seul. Les quatre candidats
  à vérifier en priorité : `ena`/`xen_netfront` chargés, les règles udev
  `amazon-ec2-utils`, `boot.zfs.devNodes`, et `networking.timeServers`. Un assert
  qui ne distingue pas STC d'un défaut est **supprimé**, et sa suppression écrite
  dans l'en-tête du fichier. C'est la méthode qui a disqualifié une dizaine
  d'asserts en v0.14.0.
- **PF-4** — Relever les trois `drvPath` de schematics **avant** le premier
  commit, pour que l'identité du gate soit une comparaison et pas une affirmation.
