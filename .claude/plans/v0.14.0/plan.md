# Plan v0.14.0 — « Les épreuves, palier 1 »

> Process : [PROCEDURE_PLANS.md](../../../PROCEDURE_PLANS.md) → *Tests — what
> replaces TDD* et *Adding a New Cogitator* (étape 6). Ledger :
> [`progress.md`](progress.md).
>
> Lot choisi par l'utilisateur parmi quatre, le 2026-10-17 : **#48 vm, #49 plasma,
> #44 gaming, #45 dreadnought** — quatre `nixosTest` manquants sur le patron
> existant.
>
> **Un plan pour le lot, une branche et une PR par issue :**
>
> | Chantier | Issue | Branche |
> |---|---|---|
> | 1 | [#48](https://github.com/gfriloux/stc/issues/48) | `test/proving-vm` |
> | 2 | [#49](https://github.com/gfriloux/stc/issues/49) | `test/proving-plasma` |
> | 3 | [#44](https://github.com/gfriloux/stc/issues/44) | `test/proving-gaming` |
> | 4 | [#45](https://github.com/gfriloux/stc/issues/45) | `test/proving-dreadnought` |

---

## Context

`CLAUDE.md` (« Adding a new cogitator », étape 6) et `PROCEDURE_PLANS.md`
(« Tests — what replaces TDD ») disent la même chose : **tout cogitator livre son
proving, dans le même changement, pas en suivi** — « a cogitator claims a
bootable use case and the proving is what makes the claim checkable ».

Mesuré sur l'arbre courant : `provings/` contient `hardening.nix`,
`docker-server.nix`, `workstation.nix` — **3 provings pour 11 cogitators**
(9 NixOS + 2 Home Manager). La règle n'est pas tenue sur l'existant, l'audit
hebdomadaire la re-signale à chaque passage (#44→#50, puis #83 le 2026-10-13), et
chaque session de backlog repousse le lot au motif qu'il est gros.

Ce plan rembourse la moitié de la dette : les quatre cogitators NixOS dont le
proving tient dans le patron déjà éprouvé. Restent pour un palier 2 — hors lot,
explicitement — `#46`/`#47` (sarcophages : build d'image + boot, mécanisme neuf)
et `#50`/`#83` (Home Manager : mécanisme neuf aussi).

Résultat attendu : `just test` passe de 3 à 7 provings, et les quatre issues se
ferment chacune par sa PR.

## Type et taille

**Architectural** → plan file. Un proving pour un cogitator existant est
*bounded* dans la table de *Sizing a Change*, mais le lot touche deux choses qui
ne le sont pas : la **structure du registre** `provings/default.nix` (une
instance nixpkgs `allowUnfree` scopée, décision 1) et la **priorité d'une option
de relique** (`relics/nixos/aws.nix`, décision 4). Le cliquet ne descend pas :
plan file.

**Un plan pour le lot, une branche et une PR par issue** — c'est la règle de
[[feedback-one-issue-at-a-time]] telle qu'amendée le 2026-10-11 : ce qui est
interdit, c'est de mélanger deux issues dans une branche, pas d'enchaîner un lot
que l'utilisateur a choisi. Les quatre chantiers partagent une seule méthode,
donc un seul plan et un seul ledger ; chacun garde sa branche, sa PR et son
merge, relus isolément.

> **Deux arbitrages validés par l'utilisateur avant exécution :** la forme « un
> plan pour le lot, une branche/PR par issue » (ci-dessus), et la décision 4
> (`mkDefault` dans `relics/nixos/aws.nix` plutôt qu'un `mkForce` de contournement
> dans le proving). À reporter dans le ledger.

## Prémisses mesurées (nixpkgs verrouillé, `nix eval` ce jour)

Toutes les sondes ont été passées en évaluation sur un `pkgs.testers.runNixOSTest`
jetable, cogitator par cogitator. Ce qui a été trouvé :

| Fait mesuré | Conséquence |
|---|---|
| `cogitator-vm` et `cogitator-plasma` évaluent **tels quels** comme nœud de test (`drvPath` obtenu) | Aucun aménagement : deux provings au patron strict. |
| `cogitator-gaming` **échoue** : `steam` est unfree, et le `pkgs` de `perSystem` n'autorise pas l'unfree | Blocage réel, décision 1. |
| `nixpkgs.config.allowUnfree = true` **dans le nœud** → `error: nixpkgs.config is set to read-only` | La voie du nœud est fermée, mesurée fermée. |
| `node.pkgs = pkgsUnfree` → `error: node.pkgs is defined multiple times` (posé par `runNixOSTest` lui-même) | Demanderait un `mkForce`. Écartée. |
| `pkgsUnfree.testers.runNixOSTest { … }` → `drvPath` obtenu | **La voie retenue**, et c'est déjà le patron de `forge/default.nix:41-45` (`pkgs-unfree` scopé pour Terraform BSL). |
| `cogitator-dreadnought` échoue sur `Failed assertions: ZFS requires networking.hostId to be set` | Le nœud pose `networking.hostId`, comme le font les trois schematics. |
| Puis conflit : `systemd.services."serial-getty@ttyS0".enable` — `false` (test-instrumentation) vs `true` à priorité normale (`relics/nixos/aws.nix:82`) | Décision 4. |
| Avec les deux correctifs, `cogitator-dreadnought` évalue (`drvPath` obtenu) | Le chantier est faisable. |
| Dans le nœud dreadnought, `fileSystems` = `["/" "/nix/.ro-store" "/nix/.rw-store" "/nix/store" "/tmp/shared" "/tmp/xchg"]` et `boot.loader.grub.device` = `/dev/disk/by-id/virtio-root` | Le `mkVMOverride` du module qemu-vm **remplace** les montages ZFS *et* le device GRUB du cogitator. Ni les datasets ni le disque EBS ne sont observables → note de portée obligatoire (même classe que celle de `provings/hardening.nix`). |
| `boot.kernelParams` du nœud dreadnought contient `console=ttyS0,115200n8`, `nvme_core.io_timeout=4294967295`, `random.trust_cpu=on` | Les trois paramètres de la relique AWS **survivent** → assertables dans `/proc/cmdline`. |
| `services.timesyncd.enable = false` et pas de `/etc/resolv.conf` dans le nœud dreadnought ; `usePredictableInterfaceNames` ramené à `false` | `networking.timeServers = ["169.254.169.123"]` et les résolveurs Quad9 **ne sont pas** observables au runtime. Note de portée, pas d'assert décoratif. |
| Unités présentes dans le nœud dreadnought : `stc-grow-pool`, `zpool-trim` ; `zfs` dans `systemPackages` ; `kernel.kptr_restrict = 2` ; `sshd` `PermitRootLogin = "no"` ; kernel 6.12.111 (pin ZFS) | C'est **ça** que le proving dreadnought peut prouver. |
| Nœud `vm` : `admin` shell `fish-4.9.3`, groupes `["wheel"]`, `linger = true`, `sshd` activé, `docker` **off**, `nix.gc.automatic = true` / `dates = ["weekly"]` / `options = "--delete-older-than 5d"`, `nix.optimise.automatic = true`, `/etc/nix/nix.conf` → `experimental-features = nix-command flakes` | Valeurs exactes des asserts du proving vm. |
| Nœud `vm` avec `docker.enable = true` : groupes `["wheel" "docker"]`, `virtualisation.docker.enable = true` | Le deuxième nœud prouve le chemin opt-in. |
| Nœud `plasma` : `/etc/sddm.conf.d/00-nixos.conf` contient `DisplayServer=wayland` et `DefaultSession=plasma.desktop` ; `/etc/xdg/xdg-desktop-portal/portals.conf` = `[preferred]\ndefault=*` ; unités utilisateur `pipewire.service`, `pipewire.socket`, `pipewire-pulse.*`, `wireplumber.service` ; `services.pulseaudio.enable = false` | Chemins exacts des asserts du proving plasma. |
| Nœud `gaming` : `hardware.steam-hardware.enable = true`, `steam` dans `systemPackages`, `systemd.tmpfiles.settings."graphics-driver"` crée `/run/opengl-driver` **et** `/run/opengl-driver-32` ; `remotePlay = false` → `allowedUDPPortRanges = []` ; `remotePlay = true` → `[{from = 27031; to = 27035;}]` (et **aucun** range TCP) | Asserts du proving gaming, y compris les bornes exactes du pare-feu. |
| Coût de build mesuré (`--dry-run`) : vm ≈ 449 MiB à télécharger, dreadnought ≈ 273 MiB, gaming ≈ 1.3 GiB | `just test` devient nettement plus lourd ; plasma (KDE) est le plus gros, et le proving `workstation` tire déjà ce closure. |

## Décisions

### 1. L'unfree de `steam` : une instance nixpkgs scopée dans le registre

`provings/default.nix` construit le proving `gaming` avec
`pkgs-unfree.testers.runNixOSTest`, où
`pkgs-unfree = import inputs.nixpkgs { inherit system; config.allowUnfree = true; }`.
Les trois autres provings restent sur le `pkgs` de `perSystem`.

Pourquoi celle-là : les deux autres voies sont **mesurées fermées**
(`nixpkgs.config` est read-only dans un nœud ; `node.pkgs` est déjà défini par
`runNixOSTest`), et ce patron existe déjà dans le dépôt — `forge/default.nix`
l'utilise pour Terraform avec exactement le même argument écrit en commentaire
(« Scope it narrowly to avoid accidentally allowing other unfree packages across
the board »). On ne relâche pas l'unfree à l'échelle du flake : seule la ligne
`gaming` du registre le voit.

Le fichier `provings/gaming.nix` reste donc identique de forme aux trois autres
(`{self}: { name; nodes; testScript; }`) : l'exception vit dans le registre, où
elle est lisible, pas dispersée dans le proving.

### 2. Le proving `vm` a deux nœuds

`machine` (défauts) et `dockervm` (`docker.enable = true`). Le cogitator
documente le fait que l'appartenance au groupe `docker` **équivaut à root**, et
c'est la raison pour laquelle l'option est opt-in ; un proving à un seul nœud ne
prouverait qu'une moitié de cette phrase. Les deux nœuds partagent presque tout
leur closure, le surcoût est le démarrage d'une seconde VM.

### 3. Le proving `plasma` assert le câblage, pas la session graphique

Même note de portée que `provings/workstation.nix` : on attend
`multi-user.target`, pas une session Plasma. Ce que `plasma` ajoute par rapport à
`workstation` — qui ne vérifie que l'existence de `display-manager.service` — ce
sont les **revendications propres de la relique** : SDDM en Wayland avec la
session Plasma par défaut, le portail XDG configuré en `default=*`, les unités
utilisateur Pipewire/WirePlumber en place, PulseAudio absent. Et il prouve la
composition **seule**, sans le socle de durcissement, qui est ce que l'issue #49
nomme.

### 4. `serial-getty@ttyS0` : corriger la relique, pas contourner dans le test

`relics/nixos/aws.nix:82` pose `systemd.services."serial-getty@ttyS0".enable =
true` à priorité normale. Mesuré : ça entre en conflit dur avec
`test-instrumentation.nix`, qui pose `false` à la même priorité — donc **aucun
consommateur ne peut désactiver le getty série sans `mkForce`**, et un nixosTest
ne peut pas du tout.

Décision : `lib.mkDefault true` dans la relique, et **aucun override dans le
proving**. Impact mesurable sur un consommateur qui ne change rien : la valeur
reste `true` (priorité plus basse, mais aucune autre définition) — à vérifier par
identité de `drvPath` sur les trois schematics, c'est le gate du Step 4.1. La
racine du frottement est la priorité de la relique ; un `mkForce` dans le test
l'aurait masquée (règle « pas de correctif avant la cause racine »).

Le commentaire de la relique doit dire *pourquoi* `mkDefault`, sinon quelqu'un le
« simplifiera » en `true` : une VM de test possède son propre `ttyS0` (c'est son
canal d'instrumentation), un hôte EC2 réel garde le getty.

### 5. Ce que le proving `dreadnought` ne prouvera pas, et pourquoi c'est écrit

Mesuré : le module qemu-vm remplace `fileSystems` **et** `boot.loader.grub.device`,
et le socle de test désactive `timesyncd` et les noms d'interfaces prévisibles.
Donc : import du pool, montage des datasets `/`, `/nix`, `/persist`, device GRUB
EBS, endpoint NTP AWS et résolveurs Quad9 sont **hors de portée**, pour des
raisons de framework et non de code.

Le proving assert ce qui reste, et c'est substantiel : le profil composé **boote**
(c'est la revendication centrale de #45), le noyau compatible ZFS démarre
réellement (`modprobe zfs` puis `zpool status`), les trois paramètres noyau AWS
sont dans `/proc/cmdline`, l'unité d'agrandissement de pool `stc-grow-pool` et
`zpool-trim` existent, `udisks2` est absent, le durcissement traverse le profil
(`kernel.kptr_restrict = 2`, `sshd -T` → `permitrootlogin no`).

Le vrai banc pour la couche disque reste le qcow2 de `schematics/local-vm`, comme
en v0.13.0 pour #70. La note de portée du proving doit le dire et y renvoyer.

### 6. Le rollback d'impermanence : on le laisse tourner et on l'observe

`boot.initrd.systemd.services.zfs-rollback` est bien dans le nœud (mesuré). Dans
la VM de test il n'y a pas de pool `vmpool`, donc le script échouera. L'unité est
tirée par `wantedBy = ["initrd.target"]` (un *Wants*, pas un *Requires*), donc le
boot ne devrait pas se bloquer — **non vérifié en évaluation, ça demande le
build**, qui est la commande de vérification du Step 4.2.

Assert visé : le journal fusionné de l'initrd montre que l'unité a tourné
(`journalctl -b | grep "Rollback vmpool/root to @blank"`) et `multi-user.target`
est quand même atteint. Si le build montre que l'échec bloque le boot, la règle
qui s'applique est « pas de quatrième tentative » : on acte dans le ledger la
réduction de portée (`stc.relics.impermanence.enable = lib.mkForce false` dans le
nœud + note de portée) et on la remonte dans le message de clôture. C'est une
décision prévue, pas un TBD.

## Architecture

Aucune frontière de `DESIGN.md` déplacée. `provings/` est de la QA interne, hors
`nix flake check`, non exportée aux consommateurs. Les quatre nouveaux fichiers
suivent le contrat existant : une fonction `{self}: { name; nodes; testScript; }`,
le nœud important le vrai module du flake (`self.nixosModules.cogitator-<nom>`).
Deux ajustements de registre seulement : l'instance `pkgs-unfree` (décision 1) et
quatre lignes dans `provings/default.nix` + quatre dans la recette `test` du
`Justfile`. Une seule ligne de relique change (décision 4).

## Global Constraints

- Namespaces canoniques uniquement dans les nœuds : `stc.cogitator.<profil>.*`,
  `stc.relics.<domaine>.*`. Aucun alias déprécié.
- Aucune option nouvelle, aucun renommage → aucun `mkRenamedOptionModule`.
- Les trois schematics doivent continuer à évaluer, et pour la décision 4 leur
  `drvPath` doit être **identique** avant/après.
- Tout proving enregistré dans `provings/default.nix` est aussi dans la recette
  `test` du `Justfile` — sinon le vert est faux (`Justfile:57`, Gate 5).
- Les provings restent hors de `just ci`.
- Aucun secret : les nœuds n'ont ni clé privée ni mot de passe hors des paires
  snakeoil de nixpkgs (`nixos/tests/ssh-keys.nix`) si une authentification est
  nécessaire.
- Chaque proving porte en tête un commentaire de portée disant ce qu'il ne prouve
  pas et pourquoi — c'est le style établi par les trois existants.

## Review Focus

Les modes de défaillance qu'aucune commande de step n'exerce :

- **La relique AWS (décision 4) est la seule ligne qui sort de `provings/`.**
  `mkDefault` affaiblit la garantie « ce profil vous donne une console série » :
  n'importe quelle définition tierce gagne désormais sans `mkForce`. L'argument
  est que c'est précisément le but, mais c'est un changement de contrat pour les
  consommateurs de `relics.aws` et `cogitator.dreadnought`, et il doit être dit
  dans la PR et la note de release, pas seulement dans le ledger.
- **Un proving qui passe pour une raison décorative.** Pour chaque assert, se
  demander ce qu'il interdirait : `systemctl cat` lit un fichier sur disque et
  réussit même si l'unité ne démarre jamais (c'est assumé et documenté dans
  `docker-server`), mais un assert sur une valeur que le framework pose lui-même
  ne prouve rien du tout. Les candidats repérés : NTP, résolveurs,
  `usePredictableInterfaceNames` — déjà exclus par la décision 5, à ne pas
  réintroduire par confort.
- **Le coût de `just test`.** On passe de 3 à 7 VM, dont KDE et Steam. Si la
  recette devient trop lourde pour être lancée en fin de branche, la discipline
  « `just test` avant de fermer une branche qui touche un cogitator » s'érode en
  silence. À dire explicitement dans la doc (Step 5) avec les chiffres mesurés.
- **`dockervm` et `machine` dans le même proving** : vérifier que l'assert
  « docker absent » tombe bien sur `machine` et pas sur un nœud où il est allumé —
  une inversion rendrait le proving vert et faux.
- **Le pare-feu de `gaming`** : les bornes mesurées sont `27031–27035` en UDP et
  **rien** en TCP. Écrire `27036` ou un range TCP par mimétisme avec la doc Steam
  donnerait un assert rouge pour une mauvaise raison.

## Affected Files

- [ ] `provings/vm.nix` — nouveau (#48)
- [ ] `provings/plasma.nix` — nouveau (#49)
- [ ] `provings/gaming.nix` — nouveau (#44)
- [ ] `provings/dreadnought.nix` — nouveau (#45)
- [ ] `provings/default.nix` — 4 entrées + l'instance `pkgs-unfree`
- [ ] `Justfile` — 4 lignes dans la recette `test`
- [ ] `relics/nixos/aws.nix` — `mkDefault` sur `serial-getty@ttyS0` (#45)
- [ ] `docs/src/content/docs/en/provings/index.md` — table de couverture, notes de portée, procédure « Adding a proving » (il manque aujourd'hui l'étape `Justfile`)
- [ ] `docs/src/content/docs/fr/provings/index.md` — miroir
- [ ] `.claude/plans/v0.14.0/plan.md` + `progress.md` — ce plan et son ledger

---

## Chantier 1 — `#48` proving `vm` · branche `test/proving-vm`

### Step 1.1 — `provings/vm.nix` à deux nœuds

**Description :** nouveau proving, deux nœuds (décision 2), commentaire de tête
sur le modèle des trois existants : ce qui est prouvé, et la note de portée
(`fileSystems` remplacé par le module qemu-vm, donc rien sur les montages).

Nœud `machine` (défauts du cogitator), subtests et valeurs **mesurées** :

- `utilisateur primaire` : `id -nG admin` contient `wheel` et **pas** `docker` ;
  `getent passwd admin` finit par un shell `fish` ; `test -f /var/lib/systemd/linger/admin`
  (l'option `linger` vaut `true` par défaut).
- `accès distant` : `wait_for_unit("sshd.service")` ou `wait_for_open_port(22)`.
- `entretien du store` : `systemctl cat nix-gc.timer` contient `OnCalendar=weekly` ;
  `systemctl cat nix-gc.service` contient `--delete-older-than 5d` ;
  `systemctl cat nix-optimise.timer` réussit.
- `flakes` : `/etc/nix/nix.conf` contient `experimental-features = nix-command flakes`.
- `docker opt-in` : `machine.fail("systemctl cat docker.service")` — c'est
  l'assert qui donne son sens au défaut `false`.

Nœud `dockervm` (`stc.cogitator.vm.docker.enable = true`) :

- `id -nG admin` contient `docker` ; `wait_for_unit("docker.socket")` puis
  `succeed("docker info")` ; `docker-compose --version` réussit (le cogitator
  n'ajoute ce paquet que sur ce chemin).

**Files changed :** `provings/vm.nix`

**Interfaces :**
- Consomme : `self.nixosModules.cogitator-vm`, `stc.cogitator.vm.{enable,docker.enable}`.
- Produit : `provings/vm.nix` comme fonction `{self}: {name; nodes; testScript;}`,
  attendue par le Step 1.2.

**Verification command(s) :**
```bash
# forme déjà mesurée sur une sonde équivalente (drvPath obtenu)
nix build .#legacyPackages.x86_64-linux.provings.vm -L --no-write-lock-file
```

**Commit message :** `test(provings): prove the vm base profile boots as claimed`

---

### Step 1.2 — Enregistrement et recette

**Description :** `vm = pkgs.testers.runNixOSTest (import ./vm.nix {inherit self;});`
dans `provings/default.nix`, et la ligne correspondante dans la recette `test`
du `Justfile`.

**Files changed :** `provings/default.nix`, `Justfile`

**Interfaces :**
- Consomme : `provings/vm.nix` (Step 1.1).
- Produit : `legacyPackages.x86_64-linux.provings.vm`.

**Verification command(s) :**
```bash
nix flake show --no-write-lock-file 2>/dev/null | grep -A2 provings
just test   # doit bâtir 4 provings, dont vm
```

**Commit message :** `test(provings): register the vm proving in the suite`

---

## Chantier 2 — `#49` proving `plasma` · branche `test/proving-plasma`

### Step 2.1 — `provings/plasma.nix`

**Description :** nouveau proving, un nœud, `wait_for_unit("multi-user.target")`
(décision 3 : pas de session graphique), commentaire de tête renvoyant à la note
de portée de `workstation` et disant ce que celui-ci ajoute.

Subtests, chemins **mesurés** :

- `SDDM en Wayland` : `/etc/sddm.conf.d/00-nixos.conf` contient `DisplayServer=wayland`
  **et** `DefaultSession=plasma.desktop` ; `systemctl cat display-manager.service`
  mentionne `sddm`.
- `session Plasma installée` : le `SessionDir` du fichier ci-dessus pointe sur un
  `share/wayland-sessions` existant → `test -e "$(...)/plasma.desktop"`, ou plus
  simplement `test -e /run/current-system/sw/share/wayland-sessions/plasma.desktop`
  si le paquet de session est dans le profil système (à trancher au build, les
  deux chemins sont dans la configuration mesurée).
- `portail XDG` : `/etc/xdg/xdg-desktop-portal/portals.conf` contient `default=*`.
- `audio` : `test -e /etc/systemd/user/pipewire.service`,
  `test -e /etc/systemd/user/wireplumber.service`,
  `systemctl cat rtkit-daemon.service` réussit, et
  `test ! -e /etc/systemd/user/pulseaudio.socket` (la relique coupe PulseAudio).
- `WirePlumber dans la session` : `test -e /etc/systemd/user/default.target.wants/wireplumber.service` —
  c'est l'assert précis de la ligne `wantedBy = ["default.target"]` de la relique,
  la seule décision STC du fichier.

**Files changed :** `provings/plasma.nix`

**Interfaces :**
- Consomme : `self.nixosModules.cogitator-plasma`, `stc.cogitator.plasma.enable`.
- Produit : la fonction attendue par le Step 2.2.

**Verification command(s) :**
```bash
nix build .#legacyPackages.x86_64-linux.provings.plasma -L --no-write-lock-file
```

**Commit message :** `test(provings): prove the plasma desktop profile wiring`

---

### Step 2.2 — Enregistrement et recette

**Description :** entrée `plasma` dans `provings/default.nix` + ligne dans la
recette `test`.

**Files changed :** `provings/default.nix`, `Justfile`

**Interfaces :** consomme `provings/plasma.nix` (Step 2.1) ; produit
`legacyPackages.x86_64-linux.provings.plasma`.

**Verification command(s) :**
```bash
just test
```

**Commit message :** `test(provings): register the plasma proving in the suite`

---

## Chantier 3 — `#44` proving `gaming` · branche `test/proving-gaming`

### Step 3.1 — L'instance `pkgs-unfree` du registre

**Description :** dans `provings/default.nix`, ajouter `inputs` aux arguments du
module flake-parts et
`pkgs-unfree = import inputs.nixpkgs {inherit system; config.allowUnfree = true;}`,
avec le commentaire qui porte la décision 1 : les deux autres voies sont mesurées
fermées (`nixpkgs.config` read-only dans un nœud, `node.pkgs` déjà défini par
`runNixOSTest`), et le patron vient de `forge/default.nix`.

**Files changed :** `provings/default.nix`

**Interfaces :**
- Produit : `pkgs-unfree` dans la portée du registre, consommé par le Step 3.3.
- Ne touche **aucun** des trois provings existants, qui restent sur `pkgs`.

**Verification command(s) :**
```bash
# les trois provings existants gardent un drvPath identique (l'instance ajoutée
# ne doit rien contaminer) — mesurer avant/après et comparer
nix eval .#legacyPackages.x86_64-linux.provings.hardening.drvPath --no-write-lock-file
nix eval .#legacyPackages.x86_64-linux.provings.docker-server.drvPath --no-write-lock-file
nix eval .#legacyPackages.x86_64-linux.provings.workstation.drvPath --no-write-lock-file
```

**Commit message :** `chore(provings): add a narrowly scoped unfree pkgs instance`

---

### Step 3.2 — `provings/gaming.nix`

**Description :** nouveau proving, deux nœuds, commentaire de tête : Steam est
unfree (renvoi à la décision du registre) et la portée est le câblage, pas le
lancement d'un jeu.

Nœud `machine` (`stc.cogitator.gaming.enable = true`), valeurs **mesurées** :

- `steam câblé` : `test -e /run/current-system/sw/bin/steam` ; les règles udev de
  `hardware.steam-hardware` sont présentes (`hardware.steam-hardware.enable`
  mesuré `true` → `grep -r steam /etc/udev/rules.d/` ou le chemin exact relevé au
  premier build).
- `pilotes 32 bits` : `test -L /run/opengl-driver-32` **et** `test -L /run/opengl-driver`
  (mesuré : `systemd.tmpfiles.settings."graphics-driver"` crée les deux liens ;
  c'est la revendication `enable32Bit` de la relique AMD, celle dont Proton
  dépend).
- `pipewire` : mêmes asserts d'unités utilisateur que le proving plasma, puisque
  le cogitator compose la même relique.
- `remote play fermé par défaut` : `iptables -S` (ou `nft list ruleset`) ne
  mentionne pas `27031`.

Nœud `remoteplay` (`steam.remotePlay = true`) : le range **UDP 27031–27035** est
ouvert, et aucun range TCP n'est ajouté (bornes mesurées — ne pas écrire 27036).

**Files changed :** `provings/gaming.nix`

**Interfaces :**
- Consomme : `self.nixosModules.cogitator-gaming`,
  `stc.cogitator.gaming.{enable,steam.remotePlay}`.
- Produit : la fonction attendue par le Step 3.3.

**Verification command(s) :**
```bash
nix build .#legacyPackages.x86_64-linux.provings.gaming -L --no-write-lock-file
# ≈ 1.3 GiB à télécharger la première fois (mesuré par --dry-run)
```

**Commit message :** `test(provings): prove the gaming profile wiring`

---

### Step 3.3 — Enregistrement et recette

**Description :** `gaming = pkgs-unfree.testers.runNixOSTest (import ./gaming.nix {inherit self;});`
— seule ligne du registre à utiliser `pkgs-unfree` — plus la ligne dans la
recette `test`.

**Files changed :** `provings/default.nix`, `Justfile`

**Interfaces :** consomme `pkgs-unfree` (Step 3.1) et `provings/gaming.nix`
(Step 3.2) ; produit `legacyPackages.x86_64-linux.provings.gaming`.

**Verification command(s) :**
```bash
just test
```

**Commit message :** `test(provings): register the gaming proving in the suite`

---

## Chantier 4 — `#45` proving `dreadnought` · branche `test/proving-dreadnought`

### Step 4.1 — `mkDefault` sur le getty série de la relique AWS

**Description :** `relics/nixos/aws.nix:82` →
`systemd.services."serial-getty@ttyS0".enable = lib.mkDefault true;` avec le
commentaire de la décision 4 (pourquoi `mkDefault`, et qui gagne légitimement :
une VM de test possède son `ttyS0`).

**Files changed :** `relics/nixos/aws.nix`

**Interfaces :**
- Produit : `systemd.services."serial-getty@ttyS0".enable` surchargeable sans
  `mkForce`, consommé par le Step 4.2 (le nœud n'aura aucun override).

**Verification command(s) :**
```bash
# 1. la valeur ne change pas pour un consommateur qui ne change rien
nix eval ./schematics/aws-ami#nixosConfigurations.aws-ami.config.systemd.services."serial-getty@ttyS0".enable --no-write-lock-file
# attendu : true  (mesuré avant changement : true)

# 2. identité des artefacts — relever les drvPath AVANT le commit et comparer
nix eval ./schematics/aws-ami#nixosConfigurations.aws-ami.config.system.build.awsImage.drvPath --no-write-lock-file
nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.system.build.qcow2.drvPath --no-write-lock-file
```

**Commit message :** `fix(relics/aws): make the serial getty overridable`

---

### Step 4.2 — `provings/dreadnought.nix`

**Description :** nouveau proving, un nœud, commentaire de tête portant la note
de portée de la décision 5 **au complet** : `fileSystems` et
`boot.loader.grub.device` sont remplacés par le module qemu-vm (valeurs mesurées
citées), `timesyncd` et les noms d'interfaces prévisibles sont neutralisés par le
socle de test, donc import de pool, montages de datasets, device EBS, endpoint NTP
AWS et résolveurs Quad9 sont hors de portée — le banc de la couche disque est le
qcow2 de `schematics/local-vm`.

Nœud : `stc.cogitator.dreadnought.enable = true` + `networking.hostId = "deadbeef"`
(exigé par l'assertion ZFS, mesuré), **aucun** override de getty (Step 4.1).

Subtests, tous **mesurés** présents dans la configuration du nœud :

- `le profil composé boote` : `wait_for_unit("multi-user.target")` — la
  revendication centrale de #45.
- `noyau compatible ZFS` : `modprobe zfs` réussit et `zpool status` répond (pas de
  pool) — prouve que le noyau pinné par la relique ZFS (6.12.111 mesuré) démarre
  vraiment avec son module.
- `plateforme AWS` : `/proc/cmdline` contient `console=ttyS0,115200n8`,
  `nvme_core.io_timeout=4294967295` et `random.trust_cpu=on` ;
  `systemctl cat stc-grow-pool.service` réussit (agrandissement du pool EBS) ;
  `systemctl cat zpool-trim.timer` réussit ; `machine.fail("systemctl cat udisks2.service")`.
- `le durcissement traverse le profil` : `sysctl -n kernel.kptr_restrict` vaut `2`
  et `sshd -T | grep -i permitrootlogin` donne `no` — deux sondes, pas la matrice
  complète : c'est le proving `hardening` qui la couvre, ici on prouve seulement
  que la composition la transporte.
- `rollback d'impermanence câblé dans l'initrd` : `journalctl -b` contient
  `Rollback vmpool/root to @blank` (description de l'unité). Décision 6 : si le
  build montre que l'échec de l'unité bloque le boot, acter dans le ledger la
  réduction de portée (`stc.relics.impermanence.enable = lib.mkForce false` + note)
  et la remonter dans le message de clôture.

**Files changed :** `provings/dreadnought.nix`

**Interfaces :**
- Consomme : `self.nixosModules.cogitator-dreadnought`,
  `stc.cogitator.dreadnought.enable`, et le `mkDefault` du Step 4.1.
- Produit : la fonction attendue par le Step 4.3.

**Verification command(s) :**
```bash
nix build .#legacyPackages.x86_64-linux.provings.dreadnought -L --no-write-lock-file
# ≈ 273 MiB à télécharger (mesuré). C'est ce build qui tranche la décision 6.
```

**Commit message :** `test(provings): prove the dreadnought profile boots composed`

---

### Step 4.3 — Enregistrement et recette

**Description :** entrée `dreadnought` dans `provings/default.nix` + ligne dans
la recette `test`.

**Files changed :** `provings/default.nix`, `Justfile`

**Interfaces :** consomme `provings/dreadnought.nix` (Step 4.2) ; produit
`legacyPackages.x86_64-linux.provings.dreadnought`.

**Verification command(s) :**
```bash
just test   # 7 provings
```

**Commit message :** `test(provings): register the dreadnought proving in the suite`

---

## Step 5 — Documentation EN + FR (une fois par chantier, dans sa branche)

**Description :** `docs/src/content/docs/{en,fr}/provings/index.md` :

1. Une ligne dans la table **Coverage** par proving ajouté, décrivant ce qu'il
   assert (pas ce qu'il boote).
2. Les notes de portée nouvelles, au même format que les deux existantes :
   `dreadnought` (décision 5, c'est la plus importante : elle dit où est le vrai
   banc de la couche disque) et `plasma`/`workstation` (pas de session graphique).
3. Corriger la procédure « Adding a proving » : elle liste 3 étapes et **oublie
   la recette `test` du `Justfile`**, qui est pourtant ce que `CLAUDE.md` et le
   Gate 5 exigent — un proving absent de la recette ne tourne jamais.
4. Dire le coût mesuré de `just test` après le lot (7 VM, dont KDE et Steam), pour
   que la discipline « `just test` avant de fermer une branche » reste tenable en
   connaissance de cause.

La ligne de table et la note de portée d'un chantier partent **dans la branche de
ce chantier** : chaque PR est complète et relisible seule (règle de synchronisation
doc de `CLAUDE.md`). Les points 3 et 4 partent avec le dernier chantier.

**Files changed :** `docs/src/content/docs/en/provings/index.md`,
`docs/src/content/docs/fr/provings/index.md`

**Verification command(s) :**
```bash
just docs-parity
grep -n "vm\|plasma\|gaming\|dreadnought" docs/src/content/docs/en/provings/index.md
```

**Commit message :** `docs(provings): document the <nom> proving and its scope`

---

## Quality Gates

Par branche, avant de présenter la PR :

- [ ] `just ci` (format + lint + `nix flake check` + parité doc)
- [ ] `just test` — **tous** les provings de la recette, pas seulement le nouveau
- [ ] La recette `test` contient bien le proving ajouté (sinon vert faux, Gate 5)
- [ ] Les trois schematics évaluent ; pour le chantier 4, `drvPath` **identiques**
      avant/après le `mkDefault`
- [ ] Aucune référence `stc.*` périmée (le grep filtré de `CLAUDE.md`)
- [ ] Commits atomiques, chacun vérifiable seul
- [ ] Revue par un contexte neuf sur `$(git merge-base main HEAD)..HEAD`, avec la
      section *Review Focus* ci-dessus transmise telle quelle
- [ ] Ledger `.claude/plans/v0.14.0/progress.md` à jour : une ligne par step, et
      les arbitrages des décisions 4 et 6 écrits avec leur mesure

Fin de lot :

- [ ] Les quatre issues fermées par leur PR
- [ ] `just changelog --tag v0.14.0` puis tag signé `v0.14.0`, selon
      [[project-versioning-releases]]
- [ ] Message de clôture : ce qui n'est **pas** prouvé (décisions 5 et 6), le
      changement de contrat de la relique AWS (décision 4), et le palier 2 restant
      (#46, #47, #50, #83)

## Pre-flight scan

À faire avant le Step 1.1, une ligne de ledger par paire :

- 1.1 → 1.2 : `provings/vm.nix` exporte `{self}: {name; nodes; testScript;}` ;
  le registre l'importe avec `import ./vm.nix {inherit self;}`. Même forme pour
  2.1→2.2, 3.2→3.3, 4.2→4.3.
- 3.1 → 3.3 : le nom `pkgs-unfree` est écrit identiquement dans le `let` du
  registre et dans la ligne `gaming`.
- 4.1 → 4.2 : le nœud dreadnought ne contient **aucune** définition de
  `systemd.services."serial-getty@ttyS0"` — c'est tout l'intérêt du Step 4.1.

## Ordre et livraison

`#48 vm` → `#49 plasma` → `#44 gaming` → `#45 dreadnought`. Du plus certain au
plus risqué : les deux premiers évaluent déjà sans aménagement, le troisième
porte la décision unfree, le dernier touche une relique et porte les deux notes
de portée.

Une branche, une PR, un merge par issue, avec la main rendue entre deux chantiers
(l'utilisateur merge lui-même, cf. [[feedback-delivery-commands]]). Les commandes
signées (commit, tag, merge, push) sont annoncées en lot et attendent le feu vert,
cf. [[feedback-git-interactive]].
