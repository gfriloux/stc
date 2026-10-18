# Plan v0.16.0 — chantiers 2 et 3 : les épreuves Home Manager (#83, #50)

> Process : [PROCEDURE_PLANS.md](../../../PROCEDURE_PLANS.md) → *Tests — what
> replaces TDD* et *Adding a New Cogitator* (étape 6). Ledger :
> [`proving-home-manager-progress.md`](proving-home-manager-progress.md).
>
> Lot choisi par l'utilisateur le 2026-10-18 : **#47 + #83 + #50 — « les épreuves,
> palier 2 »**. Chantier 1 (#47) dans
> [`proving-sarcophagus-aws.md`](proving-sarcophagus-aws.md).
>
> | Chantier | Issue | Branche | Couvert ici |
> |---|---|---|---|
> | 2 | [#83](https://github.com/gfriloux/stc/issues/83) | `test/proving-enginseer` | oui |
> | 3 | [#50](https://github.com/gfriloux/stc/issues/50) | `test/proving-home-desktop` | oui |
>
> **Un plan pour deux issues**, parce qu'elles partagent un mécanisme neuf dont
> les prémisses sont communes, et parce que le chantier 3 consomme une assertion
> que le chantier 2 établit. C'est la forme retenue en v0.14.0 pour les quatre
> épreuves de ce lot-là : un plan, une branche et une PR par issue.
>
> **Ordre imposé : 2 puis 3**, et pour une raison de produit, pas de commodité —
> voir décision 2.

---

## Maintenance Plan: les épreuves Home Manager

**Type :** ajout de deux épreuves (`provings/`) sur les deux cogitators Home
Manager, avec un mécanisme de test nouveau dans le dépôt.

**Goal :** `provings/enginseer.nix` et `provings/home-desktop.nix` démarrent une
VM, y **activent réellement** un profil Home Manager pour un utilisateur de test,
et asserte ce que chaque profil revendique au runtime.

**Why :** Home Manager a **zéro couverture** dans STC. `cogitator.home.enginseer`
est livré depuis la v0.1.0, `cogitator.home.desktop` depuis presque aussi
longtemps, et aucun des deux n'a jamais été démarré par un test. Après le palier 1
(v0.14.0) et #47, ce sont les deux derniers profils du dépôt sans épreuve : les
fermer fait tenir la règle de `CLAUDE.md` étape 6 sur **tout** l'existant.

**Architecture :** le nœud nixosTest importe
`inputs.home-manager.nixosModules.home-manager`, déclare un utilisateur de test,
et lui attache le cogitator par `home-manager.users.<u>.imports`. L'activation
devient une unité systemd ordinaire du nœud, donc observable comme n'importe
quelle autre. Aucun pilier n'est créé ni déplacé : les épreuves HM vivent dans
`provings/`, à côté des neuf autres.

## Type et taille

**Architectural** → plan file. Pas pour la taille du code (chaque fichier fait
quelques dizaines de lignes), mais parce que le chantier 2 **tranche le mécanisme
par lequel STC prouvera tout cogitator Home Manager à venir**, et que #50 laisse
explicitement cette question ouverte par écrit (« doesn't need to be
`runNixOSTest` if that's the wrong tool for a HM-only module »). Répondre à cette
question est une décision de méthode sur le pilier `provings/`, et elle
s'écrit dans la doc publique du pilier.

## Prémisses mesurées (nixpkgs et home-manager verrouillés, 2026-10-18)

Toutes mesurées sur des sondes jetables hors arbre, pas déduites.

| Fait mesuré | Commande / source | Conséquence |
|---|---|---|
| `inputs.home-manager.nixosModules` = `["default" "home-manager"]` | `nix eval` sur `builtins.getFlake` | Le module NixOS de HM est disponible dans l'input déjà verrouillé. **Aucun input à ajouter.** |
| Un nœud important `home-manager.nixosModules.home-manager` + `home-manager.users.proving = { imports = [self.homeModules.cogitator-enginseer]; stc.cogitator.enginseer.enable = true; home.stateVersion = "25.11"; }` **évalue**, et `config.systemd.services` gagne exactement **`home-manager-proving`** | sonde `hm-probe.nix` | Le mécanisme existe, et l'activation est une **unité systemd du nœud** — donc `wait_for_unit` s'applique, comme pour n'importe quel service. |
| Idem pour `cogitator-desktop` | sonde `hm-probe-desktop.nix` | Le mécanisme ne dépend pas du profil. |
| `home.activationPackage.drvPath` se force **sans erreur unfree** pour enginseer, pour desktop, et pour les deux composés, sous un nixpkgs à config par défaut | les trois sondes | **Ni l'un ni l'autre n'a besoin de `pkgs-unfree`.** `gaming` reste le seul cas unfree du dépôt — la note de la doc sur le scoping ne change pas. |
| Les deux clôtures d'activation **construisent** (`nix build`, exit 0) : enginseer seul, et enginseer + desktop (gimp, vlc, zen-browser compris) | `nix build` des deux `drvPath` | Le coût de construction est réel mais payé ; ce n'est pas une inconnue du chantier. |
| `useGlobalPkgs = true` + `useUserPackages = true` **change la clôture** (`drvPath` différent du défaut) et remplit `users.users.<u>.packages` | sonde `hm-probe2.nix` (`sameClosure = false`, `userProfile = true`) | Décision 3 : les deux sont posées, et les paquets deviennent assertables à un chemin déterministe (`/etc/profiles/per-user/<u>/bin`). |
| Fichiers rendus par enginseer, chemins exacts : `~/.config/fish/config.fish`, `~/.config/oh-my-posh/dracula.omp.json`, `~/.config/git/config`, `~/.config/direnv/direnv.toml`, `~/.config/direnv/lib/hm-nix-direnv.sh`, `~/.config/atuin/config.toml`, `~/.config/bat/config`, `~/.config/bat/themes/Catppuccin Frappe.tmTheme`, `~/.config/systemd/user/gpg-agent.service` | sonde `hm-probe2.nix` (`xdgFiles`, `fishFiles`) | **Cibles d'assertion nommées, pas devinées.** Aucun `grep` à l'aveugle dans un répertoire inconnu. |
| Fichiers rendus par desktop seul : `~/.config/kitty/kitty.conf`, `~/.config/systemd/user/app-com.mitchellh.ghostty.service` (+ son `overrides.conf`) — et **rien** pour zen-browser | sonde `hm-probe3.nix` (`deskXdg`) | Les reliques kitty et ghostty s'assertent sur un fichier ; **zen-browser n'a aucun fichier rendu**, donc son assert porte sur le profil utilisateur. |
| `services.gpg-agent.pinentry.package` : **`pinentry-curses`** sur enginseer seul, **`pinentry-qt`** sur enginseer + desktop | sondes 2 et 3 | **La revendication croisée des deux profils est vraie et mesurable.** C'est l'assert phare de #50 (décision 2). |
| Sur desktop **seul**, `services.gpg-agent.enable = false` et **aucune** unité `systemd/user/gpg-agent.*` n'est rendue — alors que `pinentry.package` vaut quand même `pinentry-qt` | sonde `hm-probe3.nix` | Le commentaire « inert if gpg-agent is not enabled » de `cogitator/home/desktop.nix` est exact, et **assertable** : c'est l'absence d'unité qui le prouve, pas la valeur de l'option. |
| `provings/default.nix` reçoit déjà `{self, inputs, lib, ...}` et ne passe que `{inherit self;}` à chaque épreuve | lecture du fichier | Les deux épreuves HM ont besoin d'`inputs` → leur signature est `{self, inputs}`. **Changement d'interface local**, détaillé au step 1. |

### Ce qui n'est pas encore mesuré, et qui l'est au banc

| Inconnue | Comment on la lève | Issue si elle tombe mal |
|---|---|---|
| `home-manager-<u>.service` **réussit-elle** au runtime dans la VM (l'évaluation et la construction sont acquises, l'activation non) ? | `machine.wait_for_unit("home-manager-proving.service")` puis `systemctl status` | C'est le gate PF-3. Si l'activation échoue, la **cause** est lue dans son journal avant tout contournement ; le repli documenté (construire le paquet d'activation sans l'activer) est explicitement **refusé** par la décision 1 et ne serait repris qu'avec la cause écrite au ledger. |
| Les alias fish sont-ils résolus par un fish réellement lancé, et pas seulement écrits dans `config.fish` ? | `su - proving -c "fish -c 'functions --query cat'"` | Si le fish de connexion ne source pas `config.fish` dans ce contexte, l'assert reste sur le fichier rendu **et l'en-tête dit que le runtime n'est pas prouvé** — pas un assert sur le fichier maquillé en assert de comportement. |
| `programs.fzf.historyWidget` existe-t-il dans le home-manager verrouillé (le code d'enginseer est conditionnel) ? | `nix eval` sur les options du module | Détermine laquelle des deux branches de `fzfHistoryWidget` est vivante, donc lequel des deux asserts est écrit. Les deux sont légitimes ; en asserter la mauvaise serait un faux vert. |
| Le profil HM pose-t-il `users.users.<u>.shell`, ou le nœud doit-il le faire ? | mesuré : non, HM n'y touche pas → le nœud pose `shell = pkgs.fish` | Déjà tranché : le nœud le pose, et l'en-tête dit que **le shell de connexion n'est pas une revendication du cogitator** — c'est une concession de banc, au même titre que les cinq du patron image externe. |

## Décisions

### 1. `runNixOSTest`, et pas une construction de paquet d'activation

#50 laisse le mécanisme ouvert et nomme le repli : « HM build/activation check is
acceptable ». **La réponse est non**, et c'est la décision centrale du chantier.

Construire `home.activationPackage` prouve que la configuration *évalue et
construit*. C'est précisément ce que `nix flake check` et les Purity Seals
prouvent déjà, et la doc du pilier l'écrit en ces termes : « Where `nix flake
check` and the Purity Seals prove a flake *evaluates*, the provings prove a
system *works*. » Une épreuve qui se réduirait à un `nix build` n'ajouterait
rien au gate existant tout en portant le nom d'une épreuve — le pire des deux
mondes, « ça se lit comme de la couverture ».

Or les revendications d'enginseer sont **des revendications de runtime** : un
alias `cat` qui se résout en `bat` dans un shell réellement lancé, `delta` qui
est bien le pager que `git` choisit, l'agent gpg qui démarre avec le bon
pinentry, `direnv` accroché au shell. Aucune ne se lit dans un `drvPath`.

Coût accepté : deux VM de plus dans `just test`, dont une qui porte gimp, vlc et
zen-browser. Les deux clôtures sont déjà construites et vertes (prémisses), donc
le coût est connu et non spéculatif.

### 2. Ordre 2 → 3, imposé par une revendication croisée

`cogitator/home/desktop.nix` contient :

```nix
# Graphical pinentry for gpg-agent. Overrides the headless-safe default set
# by cogitator-enginseer; inert if gpg-agent is not enabled.
services.gpg-agent.pinentry.package = lib.mkForce pkgs.pinentry-qt;
```

Cette ligne revendique **deux** choses, et aucune des deux n'est observable sur
un utilisateur qui ne porte que `desktop` :

1. Elle **gagne** contre le `mkDefault pinentry-curses` d'enginseer. Mesuré :
   `pinentry-curses` seul, `pinentry-qt` à deux. C'est une interaction entre deux
   cogitators, donc elle se prouve sur un utilisateur qui porte les deux.
2. Elle est **inerte** sans gpg-agent. Mesuré : sur `desktop` seul,
   `services.gpg-agent.enable = false` et aucune unité utilisateur `gpg-agent`
   n'est rendue, bien que `pinentry.package` vaille `pinentry-qt`. La preuve est
   donc l'**absence d'unité**, pas la valeur de l'option.

Le chantier 3 a donc besoin du nœud du chantier 2 comme moitié de son dispositif.
Sans cet ordre, #50 se réduirait à « gimp est installé », qui est à peu près une
tautologie sur une liste `home.packages`.

### 3. `useGlobalPkgs = true` et `useUserPackages = true` sur les deux nœuds

Mesuré : les deux changent la clôture, donc ce n'est pas neutre et ça se décide.

- **`useGlobalPkgs = true`** : HM utilise le `pkgs` du nœud au lieu d'importer sa
  propre instance nixpkgs. Une seule instance à l'évaluation, et surtout : la
  note publique de la doc sur le scoping unfree (« l'instance doit être celle qui
  *construit* le test ») reste vraie pour les épreuves HM aussi. Avec une seconde
  instance importée par HM, cette phrase deviendrait fausse sans que rien ne le
  signale.
- **`useUserPackages = true`** : les paquets atterrissent dans
  `users.users.<u>.packages`, donc sous `/etc/profiles/per-user/<u>/bin` —
  **un chemin déterministe**, au lieu d'un `~/.nix-profile` créé par l'activation.
  C'est ce qui rend l'assert de zen-browser (seule relique sans fichier rendu)
  écrivable autrement qu'en fouillant un profil utilisateur.

Les deux sont des **concessions de banc** au sens du patron image externe : elles
sont documentées en amont pour cet usage, et l'en-tête de chaque épreuve dit
qu'elles ne sont pas des choix du produit. Un consommateur qui ne les pose pas
obtient une configuration différente, et l'en-tête doit le dire pour que personne
ne lise l'épreuve comme une recommandation de câblage.

### 4. Ce que chaque épreuve asserte — candidats, et le tri qui vient

Le tri définitif est le gate PF-3 : **chaque candidat est mesuré sur un nœud nu
et, le cas échéant, sur un nœud portant le module amont seul, avant d'être
écrit**. C'est la méthode qui a disqualifié une dizaine d'asserts en v0.14.0 et
attrapé un assert tautologique en v0.15.0. Les candidats sont listés avec ce
qu'ils prétendent discriminer, pas comme une liste à cocher.

**`provings/enginseer.nix` (#83)** — un nœud, un utilisateur :

| Candidat | Cible mesurée | Discrimine quoi |
|---|---|---|
| l'activation a réussi | `home-manager-proving.service` active, `is-system-running` → `running` | tout le profil : une seule option HM invalide rend ceci rouge |
| les trois alias fish | `~/.config/fish/config.fish` **et** `fish -c 'functions --query cat'` | `shellAliases` du cogitator — rien en amont ne pose `cat`→`bat` |
| l'invite oh-my-posh | la ligne `oh-my-posh init fish --config …/dracula.omp.json` dans `config.fish`, **et** le JSON présent au chemin visé | le `shellInit` **et** le `xdg.configFile` pointant un fichier du dépôt |
| delta est le pager de git | `git config --get core.pager` lu *en tant que l'utilisateur* | `delta.enableGitIntegration` — c'est l'intégration, pas la présence du binaire |
| direnv est silencieux et accroché | `direnv.toml` + `direnv/lib/hm-nix-direnv.sh` + le hook dans `config.fish` | les trois sous-options (`enable`, `nix-direnv`, `silent`) |
| le pinentry sans tête | `pinentry-curses` dans `~/.config/systemd/user/gpg-agent.service` | le `mkDefault` d'enginseer — **la moitié basse de la revendication croisée** |
| ssh sans le bloc par défaut | `~/.ssh/config` porte `ControlMaster auto` et le `ControlPath` déclaré, **et pas** le bloc legacy de HM | `enableDefaultConfig = false`, qui est une revendication écrite en commentaire |
| catppuccin frappe | le thème `Catppuccin Frappe` atteint la config `bat` | `catppuccin.flavor`/`autoEnable`, et non la simple présence du module |

Candidats **écartés d'avance** parce qu'ils ne discrimineraient rien : « `bat` est
dans le PATH », « `git` est activé », « `~/.config` existe ». Une liste de
paquets prouve qu'une liste de paquets a été écrite.

**`provings/home-desktop.nix` (#50)** — **deux nœuds**, pour les deux moitiés de
la revendication croisée :

| Nœud | Candidat | Discrimine quoi |
|---|---|---|
| `desktop` seul | `~/.config/kitty/kitty.conf` rendu | la relique kitty |
| `desktop` seul | l'unité utilisateur `app-com.mitchellh.ghostty.service` + son `overrides.conf` | la relique ghostty |
| `desktop` seul | zen-browser et gimp/vlc/libnotify sous `/etc/profiles/per-user/<u>/bin` | la relique zen-browser (sans fichier rendu) et la liste `home.packages` |
| `desktop` seul | **aucune** unité `gpg-agent` utilisateur | « inert if gpg-agent is not enabled » — l'absence est la preuve |
| `desktop` + `enginseer` | `pinentry-qt` dans l'unité `gpg-agent` rendue | **le `mkForce` gagne contre le `mkDefault`** : la revendication phare |

Deux nœuds coûtent deux boots. La justification est que le second nœud est le
**seul** endroit du dépôt où une interaction entre deux cogitators est prouvée,
et que le premier est le seul endroit où le mot « inert » du commentaire devient
vérifiable. Si le coût s'avère inacceptable à la mesure, le ruling est écrit au
ledger et le nœud `desktop` seul fusionne avec le nœud composé — en perdant
l'assert « inert », perte qui se dit alors dans la doc.

### 5. Aucun fichier de `relics/` ni de `cogitator/` ne change

Même contrainte qu'au chantier 1, et même précédent : trois défauts produit sont
sortis de l'écriture d'épreuves sur les deux lots précédents. Si le banc en
révèle un, il est consigné au ledger et traité **hors** du commit de l'épreuve.

Deux endroits où c'est le plus probable ici, nommés pour qu'on les regarde :

- le `fzfHistoryWidget` conditionnel d'enginseer — si l'option n'existe pas dans
  le home-manager verrouillé, la branche vivante est la branche « rien », et le
  commentaire qui la décrit doit être vrai ;
- `programs.ssh.enableDefaultConfig = lib.mkDefault false` — un `mkDefault` dont
  le commentaire dit qu'il « matche la configuration du consommateur », donc
  exactement le motif que #86 suit.

## Global Constraints

- Les deux épreuves vivent sous `legacyPackages.<system>.provings.{enginseer,home-desktop}`
  — **hors** du gate `nix flake check` / `just ci`.
- Construites depuis le `pkgs` ordinaire de flake-parts. **Pas** `pkgs-unfree` :
  mesuré, aucun des deux profils n'en a besoin.
- Signature : `{self, inputs}: { name; nodes; testScript; }`. Les neuf autres
  gardent `{self}` — pas de migration de masse, les deux formes cohabitent et la
  raison est écrite dans `provings/default.nix`.
- Les options restent sous les deux racines sanctionnées :
  `stc.cogitator.enginseer.enable` et `stc.cogitator.desktop.enable`. **Aucune
  option nouvelle**, aucun namespace touché, donc aucun `mkRenamedOptionModule`.
- Les trois schematics continuent d'évaluer (aucun ne porte Home Manager, donc
  l'impact attendu est nul et se vérifie par identité de `drvPath`).
- Aucun secret : rien ici ne lit de fichier d'identifiants. `rbw` est activé par
  enginseer mais n'est pas configuré avec un coffre.

## Review Focus

- **Une épreuve verte pour une raison de banc.** Le risque dominant du mécanisme
  HM : `wait_for_unit` sur l'activation passe, mais rien de ce que le profil
  revendique n'est réellement en place. Mitigation : chaque assert lit un
  **fichier nommé** mesuré à l'avance, et au moins un assert par épreuve est un
  **comportement** (fish résout l'alias, git choisit delta), pas un fichier.
- **Un assert sur l'amont plutôt que sur STC.** Home Manager rend énormément de
  choses qu'aucun cogitator de STC ne demande (fontconfig, `environment.d`,
  `tray.target` — tous présents dans la sonde desktop sans qu'aucune relique ne
  les demande). Chaque candidat passe PF-3.
- **Les deux `mkDefault`/`mkForce` d'enginseer et de desktop.** Le chantier
  *prouve* une bataille de priorités ; s'il en révèle une qui n'est pas
  surchargeable alors que la doc la dit surchargeable, c'est #86 et pas ce
  chantier — à consigner, pas à corriger ici.
- **Le coût de `just test`.** Deux VM de plus, dont une avec gimp/vlc/zen-browser
  et une avec les ~40 paquets d'enginseer. Le chiffre réel est mesuré et écrit en
  doc ; si la recette devient trop lourde pour être lancée, c'est un gate qui
  cesse d'être un gate, et la doc le dit déjà.
- **Un consommateur qui ne change rien.** Zéro fichier de `relics/` ou
  `cogitator/` ne bouge. Vérifié par `git diff --name-only` et par l'identité des
  `drvPath` de schematics.

## Affected Files

- [ ] `provings/enginseer.nix` *(nouveau — chantier 2)*
- [ ] `provings/home-desktop.nix` *(nouveau — chantier 3)*
- [ ] `provings/default.nix` — registre, et le passage d'`inputs` aux deux
      nouvelles épreuves
- [ ] `Justfile` — deux lignes dans la recette `test`
- [ ] `docs/src/content/docs/en/provings/index.md`
- [ ] `docs/src/content/docs/fr/provings/index.md`

**Ne doivent pas changer :** tout `relics/**`, tout `cogitator/**`, tout
`schematics/**`, `flake.nix` (aucun input à ajouter — mesuré).

## Atomic Steps

### Chantier 2 — branche `test/proving-enginseer`

#### Step 1 : l'épreuve enginseer, son enregistrement, et le passage d'`inputs`

**Description :** écrire `provings/enginseer.nix`, l'enregistrer dans
`provings/default.nix` en lui passant `inputs`, et l'ajouter à la recette `test`.

**Pourquoi un seul commit pour les trois fichiers :** même ruling qu'en v0.15.0
— l'épreuve n'est vérifiable qu'une fois l'attribut présent, et une recette
`test` qui ne construit pas une épreuve enregistrée est un faux vert.

**Files changed :**
- `provings/enginseer.nix`
- `provings/default.nix`
- `Justfile`

**Nœud** (valeurs exactes) :

```nix
nodes.machine = {pkgs, ...}: {
  imports = [inputs.home-manager.nixosModules.home-manager];

  # Concessions de banc, pas des choix du produit — voir l'en-tête.
  users.users.proving = {
    isNormalUser = true;
    home = "/home/proving";
    shell = pkgs.fish;        # HM n'y touche pas ; sans ça, pas de fish de connexion
  };

  home-manager = {
    useGlobalPkgs = true;     # décision 3
    useUserPackages = true;   # décision 3
    users.proving = {
      imports = [self.homeModules.cogitator-enginseer];
      stc.cogitator.enginseer.enable = true;
      home.stateVersion = "25.11";
    };
  };
};
```

**Registre** dans `provings/default.nix` :

```nix
enginseer = pkgs.testers.runNixOSTest (import ./enginseer.nix {inherit self inputs;});
```

avec, au-dessus, le commentaire qui dit **pourquoi** cette épreuve reçoit
`inputs` et pas les neuf autres : le module NixOS de Home Manager vit dans un
input, et `self.homeModules.*` ne suffit pas à l'attacher à un nœud.

**Asserts :** les huit candidats de la décision 4, chacun après PF-3.

**Interfaces :**
- Consomme : `inputs.home-manager.nixosModules.home-manager` ;
  `self.homeModules.cogitator-enginseer` (enregistré dans `cogitator/default.nix`,
  injecte gitflow-toolkit, catppuccin, television-ssh) ;
  `stc.cogitator.enginseer.enable`.
- Produit : `legacyPackages.<system>.provings.enginseer` ; l'unité
  `home-manager-proving.service` observable dans le nœud ; **le patron HM que le
  step 3 réutilise** (import du module HM, `useGlobalPkgs`/`useUserPackages`,
  utilisateur nommé `proving`).

**Verification command(s) :**
```bash
nix build .#legacyPackages.x86_64-linux.provings.enginseer -L --no-write-lock-file
just test
git diff --name-only | grep -E '^(relics|cogitator|schematics)/' && echo "VIOLATION" || echo "ok"
```

**Commit message :** `test(provings): activate the enginseer profile in a VM and assert its claims`

---

#### Step 2 : la doc, EN + FR (chantier 2)

**Description :** trois endroits de `docs/*/provings/index.md`.

**Files changed :**
- `docs/src/content/docs/en/provings/index.md`
- `docs/src/content/docs/fr/provings/index.md`

**Ce qui change :**

1. **Table de couverture** — une ligne `enginseer`.
2. **Paragraphe de coût** — neuf épreuves/douze boots (après #47) → **dix/treize**,
   avec le temps mesuré.
3. **Nouvelle section « Proving a Home Manager cogitator »** — le mécanisme :
   pourquoi `runNixOSTest` et pas une construction de paquet d'activation
   (décision 1), les trois lignes de banc (`shell`, `useGlobalPkgs`,
   `useUserPackages`) avec ce que chacune achète, le nom de l'unité
   d'activation, et **la raison pour laquelle cette épreuve reçoit `inputs`** là
   où les autres reçoivent `self` seul. Plus la section « Adding a proving »,
   dont l'étape 1 dit aujourd'hui `{self}:` et doit mentionner la seconde forme.

**Interfaces :**
- Consomme : le nom d'attribut `provings.enginseer` et les asserts effectivement
  retenus au step 1.
- Produit : la section « Proving a Home Manager cogitator », que le step 4
  complète plutôt que de la dupliquer.

**Verification command(s) :**
```bash
just docs-parity
nix develop .#docs --command npm run astro check
just ci
```

**Commit message :** `docs(provings): document the Home Manager proving mechanism`

---

### Chantier 3 — branche `test/proving-home-desktop`

#### Step 3 : l'épreuve home-desktop, deux nœuds, et son enregistrement

**Description :** écrire `provings/home-desktop.nix` avec les deux nœuds de la
décision 4, l'enregistrer, l'ajouter à la recette `test`.

**Files changed :**
- `provings/home-desktop.nix`
- `provings/default.nix`
- `Justfile`

**Nœuds** (le patron HM du step 1, deux fois) :

```nix
nodes = {
  # Nœud 1 : desktop seul. Prouve les trois reliques, et que le mkForce du
  # pinentry est bien inerte sans gpg-agent (= aucune unité rendue).
  desktop = { … stc.cogitator.desktop.enable = true; … };

  # Nœud 2 : les deux profils sur le même utilisateur. Le seul endroit du dépôt
  # où une interaction entre deux cogitators est prouvée.
  composed = {
    … imports = [self.homeModules.cogitator-enginseer self.homeModules.cogitator-desktop];
      stc.cogitator = { enginseer.enable = true; desktop.enable = true; }; …
  };
};
```

**Registre :**

```nix
home-desktop = pkgs.testers.runNixOSTest (import ./home-desktop.nix {inherit self inputs;});
```

**Interfaces :**
- Consomme : le patron HM **produit par le step 1** — même import du module HM,
  mêmes `useGlobalPkgs`/`useUserPackages`, même nom d'utilisateur `proving` ;
  `self.homeModules.cogitator-desktop` et `self.homeModules.cogitator-enginseer` ;
  `stc.cogitator.desktop.enable`, `stc.cogitator.enginseer.enable` ;
  et le fait mesuré au step 1 que `pinentry-curses` est la valeur d'enginseer seul.
- Produit : `legacyPackages.<system>.provings.home-desktop`.

**Verification command(s) :**
```bash
nix build .#legacyPackages.x86_64-linux.provings.home-desktop -L --no-write-lock-file
just test
git diff --name-only | grep -E '^(relics|cogitator|schematics)/' && echo "VIOLATION" || echo "ok"
```

**Commit message :** `test(provings): prove the desktop profile and its pinentry override`

---

#### Step 4 : la doc, EN + FR (chantier 3)

**Description :** compléter ce que le step 2 a posé.

**Files changed :**
- `docs/src/content/docs/en/provings/index.md`
- `docs/src/content/docs/fr/provings/index.md`

**Ce qui change :**

1. **Table de couverture** — une ligne `home-desktop`, qui nomme la revendication
   croisée comme son contenu principal.
2. **Paragraphe de coût** — dix épreuves/treize boots → **onze/quinze** (deux
   nœuds), avec le temps mesuré. C'est la mise à jour qui compte le plus : la
   recette passe de huit à onze épreuves sur ce seul lot.
3. **Section « Proving a Home Manager cogitator »** — un paragraphe sur ce que la
   composition de deux cogitators HM sur un même utilisateur permet de prouver, et
   que l'absence d'unité est la preuve de l'inertie.
4. **Note de portée** — ce qui reste non couvert côté HM : aucune session
   graphique n'est lancée (même limite que l'épreuve `plasma`), donc kitty,
   ghostty et zen-browser sont prouvés **configurés**, pas prouvés **lancés**.

**Interfaces :**
- Consomme : la section créée au step 2 ; le nom `provings.home-desktop`.
- Produit : rien qu'un step ultérieur ne lise.

**Verification command(s) :**
```bash
just docs-parity
nix develop .#docs --command npm run astro check
just ci
```

**Commit message :** `docs(provings): record the desktop proving and the cross-profile claim`

## Quality Gates

Par chantier, avant la PR :

- [ ] `nix build .#legacyPackages.x86_64-linux.provings.<name> -L --no-write-lock-file`
- [ ] `just test` — toutes les épreuves, vert (dix après le chantier 2, onze après le 3)
- [ ] `just ci`
- [ ] Les trois schematics évaluent, et leurs `drvPath` sont **identiques**
      avant/après le chantier :
  - [ ] `nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.system.build.qcow2.drvPath --no-write-lock-file`
  - [ ] `nix eval ./schematics/aws-ami#nixosConfigurations.aws-ami.config.system.build.awsImage.drvPath --no-write-lock-file`
  - [ ] `nix eval ./schematics/dreadnought#…`
- [ ] `just docs-parity`
- [ ] `nix develop .#docs --command npm run astro check`
- [ ] `git diff --name-only` ne contient aucun chemin sous `relics/`,
      `cogitator/`, `schematics/`, ni `flake.nix`
- [ ] Revue de clôture par **contexte neuf** avant chaque PR

## Pre-flight scan

- **PF-1** — Step 1 produit le patron HM que le step 3 consomme. Vérifier que les
  deux l'écrivent **à l'identique** : même nom d'utilisateur (`proving`), même
  `home.stateVersion`, mêmes `useGlobalPkgs`/`useUserPackages`, même import
  (`inputs.home-manager.nixosModules.home-manager`, pas `.default`). Une
  divergence ici ferait que l'assert `pinentry-qt` du step 3 ne réfute pas la
  valeur mesurée au step 1.
- **PF-2** — Step 1 produit `provings.enginseer`, step 3 produit
  `provings.home-desktop` ; steps 2 et 4 consomment ces noms exacts dans la table
  de couverture **et** dans la recette citée. Orthographe : `home-desktop` (tiret),
  pas `home_desktop` ni `desktop` — ce dernier prêterait à confusion avec
  `cogitator-desktop` côté NixOS.
- **PF-3** — **Avant d'écrire chaque assert**, le mesurer : sur un nœud nu avec
  Home Manager et un utilisateur mais **sans** cogitator STC, et pour les asserts
  de composition, sur chacun des deux profils seul. Tout candidat vert sans STC
  est **supprimé**, et sa suppression écrite dans l'en-tête du fichier. Les
  candidats les plus suspects, à mesurer en premier : `fontconfig/conf.d/*`,
  `environment.d/10-home-manager.conf`, `tray.target` — tous présents dans les
  sondes sans qu'aucune relique ne les demande.
- **PF-4** — Lever les quatre inconnues de la section « Ce qui n'est pas encore
  mesuré », dans l'ordre : l'activation réussit, fish résout l'alias,
  `programs.fzf.historyWidget` existe ou non, et le shell de connexion. Une ligne
  de ledger chacune, avec la commande et sa sortie.
- **PF-5** — Relever les trois `drvPath` de schematics avant le premier commit de
  chaque chantier.
