# Plan v0.7.0 — Absorption du baseline home d'`exampleHost` dans enginseer/desktop

> Process : [PROCEDURE_PLANS.md](../../PROCEDURE_PLANS.md). Travail atomique, une
> branche, commits indépendamment vérifiables, doc synchronisée dans le même commit.
>
> **Branche :** `feat/home-baseline-v0.7.0` (une PR ; l'utilisateur merge/tag/push).

---

## Objectif

Upstreamer dans les **cogitators home** de STC ce que le consommateur `../nixos`
(home `kuri@exampleHost`) configure **à la main** et qui a vocation à être présent
**partout**. Même esprit que le plan 3-B (hardening) mais côté Home Manager :
`cogitator-enginseer` reste le **socle CLI universel** et devient un **surensemble**
du baseline d'exampleHost, `cogitator-desktop` porte les seuls réglages **spécifiques
GUI**. La future migration du consommateur (plan de suivi séparé) ne perdra alors
aucun réglage.

## Constat (analyse préalable)

Source : `../nixos/homes/x86_64-linux/kuri@exampleHost/{default.nix,ssh.nix}`.
Le home active déjà `cogitator-enginseer` + `cogitator-desktop`.

Sept éléments demandés « installés partout », routés selon l'axe **CLI/partout**
(→ enginseer) vs **spécifique GUI** (→ desktop) :

| # | Élément exampleHost | Statut STC actuel | Cible v0.7.0 |
|---|---|---|---|
| 1 | `programs.gpg.enable` | absent | enginseer (enable) |
| 2 | `programs.nix-search-tv` (+ television) | absent (enginseer a déjà `television`/`television-ssh`) | enginseer |
| 3 | `programs.gh` (git_protocol=ssh, prompt) | absent (enginseer a déjà `git`/`gitflow-toolkit`) | enginseer |
| 4 | settings `micro` (tabsize, ruler, `lsp.server=nix:nixd`…) | `micro.enable` présent, pas de settings | enginseer (settings) |
| 5 | `services.gpg-agent` | absent | enginseer (pinentry headless) + override desktop |
| 6 | SSH multiplexing (`controlMaster/Path/Persist`, `setEnv TERM`) + `.ssh/sockets/.keep` | absent | enginseer (partie universelle **seule**) |
| 7a | packages `unzip htop ouch aria2` | absents | enginseer (`home.packages`) |
| 7b | package `libnotify` | absent | desktop (`home.packages`) |

## Périmètre / hors périmètre (décidé)

**STC uniquement.** La bascule d'exampleHost sur ces cogitators (et la suppression
de ses blocs devenus redondants) est un **plan de suivi séparé**.

Restent **légitimement chez le consommateur** (spécifiques machine/user, non
réutilisables) :

- `programs.ssh.matchBlocks` des hôtes nommés (arthur/clochette/github…), leurs
  `identityFile`/secrets, et `services.ssh-agent` — **seul** le bloc multiplexing
  `matchBlocks."*"` + le dossier `sockets/` migrent.
- `home.sessionVariables.EDITOR = "micro"` — choix perso (enginseer livre micro
  *et* helix, il ne tranche pas l'éditeur par défaut).
- `programs.git.signing`/`user`, `sops`, `pgpilot`, `plasma`, `dank-shell`,
  `gtk`, l'essentiel de `home.packages` (jeux, wine, python…) — hors sujet.

## Décisions de conception (arbitrées avec l'utilisateur)

1. **Granularité : inline dans enginseer**, pas de nouveau relic. Cohérent avec le
   style actuel du profil : `atuin`, `git`, `direnv`, `rbw`, `television`… y sont
   tous `programs.X.enable` inline, **aucun** relic CLI. gpg/gh/gpg-agent/ssh
   rejoignent ce même bloc `config`. KISS, zéro nouveau fichier, zéro nouvelle
   option `stc.*` (donc **pas** de `mkRenamedOptionModule`, Gate 3 non concerné).
2. **pinentry gpg-agent : headless par défaut + override desktop.** enginseer doit
   pouvoir tourner headless/serveur (« partout »). Il pose
   `services.gpg-agent.pinentry.package = lib.mkDefault pkgs.pinentry-curses` ;
   `cogitator-desktop` l'override en `lib.mkForce pkgs.pinentry-qt` (exactement le
   `mkForce` qu'exampleHost fait déjà). L'override desktop est **inerte** si
   gpg-agent n'est pas activé → aucun couplage dur desktop→enginseer.
3. **SSH : seul le multiplexing universel.** enginseer pose `programs.ssh.enable`,
   `matchBlocks."*"` (`controlMaster="auto"`, `controlPath="~/.ssh/sockets/%r@%h:%p"`,
   `controlPersist="60m"`, `setEnv.TERM="xterm-256color"`) et
   `home.file.".ssh/sockets/.keep".text = ""`. On **ne touche pas** à
   `enableDefaultConfig` (durcissement propre au consommateur) — à surveiller à
   l'exécution (voir Risques).
4. **Défauts « profil » assumés mais neutres.** `programs.gh.settings.git_protocol`
   et les settings `micro` sont opinionnés mais adaptés à un profil dev ; posés en
   valeurs directes (le consommateur peut surcharger). `gpg-agent.enableSshSupport
   = false` (exampleHost délègue l'agent SSH à `ssh-agent`) ; `enableFishIntegration
   = true` (enginseer est un profil fish).

## Rayon d'impact interne

- Aucun schematic ne construit un home (`schematics/*` sont des `nixosConfigurations`)
  → **Gate 2 (éval schematics) sans objet** ici, exécuté seulement en sanity.
- Aucun nouveau namespace `stc.*` → **Gate 3 reste vert** par construction.
- Doc : pages `cogitator/enginseer.md` et `cogitator/desktop.md` (EN+FR) à mettre à
  jour dans les mêmes commits. Pas d'index à toucher (pas de nouveau cogitator).
- DESIGN.md (local, jamais commité) : pas de nouveau pilier, rien à ajouter.

---

## Steps atomiques (une branche, 4 commits code+doc)

### Step 1 — enginseer : gpg + gh + nix-search-tv + settings micro + packages CLI
**Commit :** `feat(cogitator-enginseer): add gpg, gh, nix-search-tv, micro settings and CLI packages`

Fichiers :
- `cogitator/home/enginseer/default.nix` — dans le bloc `programs` :
  - `gpg.enable = true;`
  - `gh = { enable = true; settings = { git_protocol = "ssh"; prompt = "enabled"; }; };`
  - `nix-search-tv = { enable = true; enableTelevisionIntegration = true; };`
  - `micro.settings = { tabsize = 2; tabstospaces = true; autoindent = true; ruler = true; savecursor = true; mouse = true; "lsp.server" = "nix:nixd"; };`
    (`micro.enable` est déjà là ; `nixd` est déjà dans `home.packages`).
  - `home.packages` += `unzip htop ouch aria2`.
- Doc (EN+FR, même commit) : `docs/src/content/docs/{en,fr}/cogitator/enginseer.md`
  — sections gpg / gh / nix-search-tv / micro + liste de paquets mise à jour.

**Vérif :** `nix flake check --no-write-lock-file` ; `nix eval .#homeModules.cogitator-enginseer --apply builtins.typeOf --no-write-lock-file`.

### Step 2 — enginseer : gpg-agent (pinentry headless)
**Commit :** `feat(cogitator-enginseer): add gpg-agent with headless-safe pinentry default`

Fichiers :
- `cogitator/home/enginseer/default.nix` — bloc `services` (nouveau) :
  ```nix
  services.gpg-agent = {
    enable = true;
    enableSshSupport = false;
    enableFishIntegration = true;
    pinentry.package = lib.mkDefault pkgs.pinentry-curses;
  };
  ```
  (`lib` est déjà dans la signature du module.)
- Doc (EN+FR) : `enginseer.md` — section gpg-agent + note « pinentry TTY par
  défaut, surchargé par `cogitator-desktop` en Qt ».

**Vérif :** `nix flake check --no-write-lock-file`.

### Step 3 — enginseer : multiplexing SSH universel
**Commit :** `feat(cogitator-enginseer): add ssh connection multiplexing`

Fichiers :
- `cogitator/home/enginseer/default.nix` :
  - `programs.ssh = { enable = true; matchBlocks."*" = { controlMaster = "auto"; controlPath = "~/.ssh/sockets/%r@%h:%p"; controlPersist = "60m"; setEnv.TERM = "xterm-256color"; }; };`
  - `home.file.".ssh/sockets/.keep".text = "";`
- Doc (EN+FR) : `enginseer.md` — section « SSH connection multiplexing » (le socket
  dir + le bloc `*` ; préciser que les `matchBlocks` d'hôtes restent chez le
  consommateur).

**Vérif :** `nix flake check --no-write-lock-file`.

### Step 4 — desktop : override pinentry Qt + libnotify
**Commit :** `feat(cogitator-desktop): override gpg-agent pinentry to Qt and add libnotify`

Fichiers :
- `cogitator/home/desktop.nix` — dans `config` :
  - `services.gpg-agent.pinentry.package = lib.mkForce pkgs.pinentry-qt;`
  - `home.packages` += `libnotify`.
- Doc (EN+FR) : `docs/src/content/docs/{en,fr}/cogitator/desktop.md` — note
  « override du pinentry gpg-agent en Qt (baseline enginseer = TTY) » + libnotify.

**Vérif :** `nix flake check --no-write-lock-file`.

---

## Risques / points à surveiller à l'exécution

- **`programs.ssh` et `enableDefaultConfig`.** Selon la version de Home Manager, activer
  `programs.ssh` sans `enableDefaultConfig` peut émettre un warning de transition.
  On **ne** pose **pas** `enableDefaultConfig = false` dans enginseer (c'est un choix
  de durcissement du consommateur) ; si HM l'exige, poser `enableDefaultConfig =
  lib.mkDefault true` (neutre) plutôt que de forcer la valeur du consommateur.
- **`micro.settings."lsp.server"`.** Dépend de `nixd` (déjà dans enginseer) — OK.
  Vérifier que la clé pointée `"lsp.server"` est bien acceptée par le module micro
  de HM (chaîne, pas attrset).
- **Merge `matchBlocks."*"`.** Tant que le consommateur garde son propre bloc `"*"`,
  il y aura double définition à la migration → traité dans le **plan de suivi**
  (suppression du bloc consommateur), hors périmètre ici.

## Gates de validation (Phase 4)

- [ ] `nix flake check --no-write-lock-file` vert
- [ ] `just ci` vert (alejandra + statix + deadnix + flake check)
- [ ] `nix eval .#homeModules.cogitator-enginseer` / `.#homeModules.cogitator-desktop`
      exposés (sanity ; les home modules ne sont pas instanciés par flake check)
- [ ] Gate 2 (schematics) : sans objet (home modules) — sanity éval des 3 schematics inchangée
- [ ] Gate 3 (namespaces) : zéro match (aucun nouveau `stc.*`)
- [ ] Gate 4 (doc) : `npm run astro check` sous `nix develop .#docs` ; parité EN/FR
- [ ] 4 commits atomiques, chacun code+doc, indépendamment vérifiable
- [ ] Sanity consommateur (optionnel) : `../nixos` rebuild home OK après bascule (plan de suivi)
- [ ] `just changelog` régénère `CHANGELOG.md` (revue avant commit ; release = user)
