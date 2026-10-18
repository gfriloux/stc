# Ledger — plan: .claude/plans/v0.16.0/proving-home-manager.md

Pre-flight (2026-10-18, avant toute branche) : chantiers 2 et 3 du lot « les
épreuves, palier 2 ». Un plan pour deux issues (#83, #50), une branche et une PR
par issue — même forme qu'en v0.14.0.

Pre-flight : le mécanisme HM a été **mesuré avant l'écriture du plan**, pas
supposé faisable. Sondes jetables hors arbre, sous le nixpkgs et le
home-manager verrouillés :
  - `inputs.home-manager.nixosModules` = `["default" "home-manager"]` → aucun
    input à ajouter au flake.
  - Un nœud important `home-manager.nixosModules.home-manager` avec
    `home-manager.users.proving.imports = [self.homeModules.cogitator-enginseer]`
    évalue, et `config.systemd.services` gagne exactement `home-manager-proving`
    → l'activation est une unité systemd ordinaire, donc `wait_for_unit`
    s'applique. Idem pour `cogitator-desktop`.
  - `home.activationPackage.drvPath` se force sans erreur unfree pour les trois
    combinaisons (enginseer, desktop, les deux) → **ni l'un ni l'autre n'a besoin
    de `pkgs-unfree`** ; `gaming` reste le seul cas unfree du dépôt.
  - `nix build` des deux clôtures d'activation (enginseer seul, enginseer +
    desktop avec gimp/vlc/zen-browser) : **exit 0 les deux**. Le coût de
    construction est payé, pas spéculatif.
  - `useGlobalPkgs = true` + `useUserPackages = true` changent le `drvPath`
    (`sameClosure = false`) et remplissent `users.users.<u>.packages` → décision 3,
    et les paquets deviennent assertables sous `/etc/profiles/per-user/<u>/bin`.
  - Chemins rendus relevés nommément (fish `config.fish`, `oh-my-posh/dracula.omp.json`,
    `git/config`, `direnv/*`, `bat/config` + thème catppuccin, `systemd/user/gpg-agent.service`
    pour enginseer ; `kitty/kitty.conf` et l'unité ghostty pour desktop, **rien**
    pour zen-browser) → les asserts visent des fichiers nommés, pas un `grep` à
    l'aveugle.
  - **La revendication croisée est vraie et mesurée** : `pinentry.package` vaut
    `pinentry-curses` sur enginseer seul et `pinentry-qt` sur les deux profils ;
    et sur desktop seul `gpg-agent.enable = false` avec **aucune** unité
    `gpg-agent` rendue, alors que `pinentry.package` vaut quand même
    `pinentry-qt`. C'est ce qui impose l'ordre 2 → 3 (décision 2) et ce qui fait
    de #50 autre chose que « gimp est installé ».

Pre-flight : `provings/default.nix` ne passe aujourd'hui que `{inherit self;}` ;
les deux épreuves HM ont besoin d'`inputs`. Changement d'interface local assumé —
les neuf autres gardent `{self}`, les deux formes cohabitent, et la raison
s'écrit dans `provings/default.nix` (step 1).

Pre-flight : aucun fichier de `relics/`, `cogitator/`, `schematics/` ni
`flake.nix` ne doit changer — vérifié contre la liste *Affected Files*.

## Chantier 2 (#83) — pre-flight exécuté le 2026-10-18

Branche `test/proving-enginseer`, ouverte sur `main` à `20b563a` (après merge de
la PR #92 du chantier 1).

**PF-5** — `drvPath` de référence des trois schematics, pour que le gate
d'innocuité soit une comparaison : `k2mxsivc…-nixos-disk-image.drv`,
`2gymzw2p…-nixos-aws-ami.drv`,
`1xnz47d7…-nixos-system-dreadnought-26.11.20260923.4975466.drv` — les mêmes
qu'au chantier 1, ce qui est attendu : aucun schematic ne porte Home Manager.

**PF-4.3 — `programs.fzf.historyWidget` existe** dans le home-manager
verrouillé. Donc la branche vivante du conditionnel `fzfHistoryWidget`
d'enginseer est celle qui pose `historyWidget.command = ""`, et c'est elle qu'il
faut vérifier. Asserter l'autre aurait été un faux vert.

**PF-3 — référence de discrimination.** Mesuré sur un nœud portant Home Manager
et un utilisateur **sans aucun cogitator STC** : `xdg.configFile` ne contient que
`environment.d/10-home-manager.conf`, trois `fontconfig/conf.d/*` et
`systemd/user/tray.target` ; `home.file` ajoute `.cache/.keep` et
`.local/state/.keep` ; `programs.fish.enable` et `services.gpg-agent.enable`
valent **`false`**. Ce sont exactement les cinq fichiers que la revue du
chantier 1 avait signalés comme pièges. **Aucune** cible d'enginseer n'existe sur
ce nœud, donc toutes discriminent.

### Deux prémisses du plan corrigées par la mesure, avant écriture

1. **Les alias `ls`/`ll`/`la`/`lt` ne sont pas à STC.** Le `config.fish` rendu en
   porte sept, mais quatre viennent du module `programs.lsd` de Home Manager.
   Seuls `cat → bat`, `cp → xcp` et `ping → prettyping` sortent des
   `shellAliases` du cogitator. Le plan parlait des « trois alias fish » sans le
   dire — l'assert ne vise que ces trois.
2. **delta n'est pas câblé sur `core.pager`.** Le plan prévoyait
   `git config --get core.pager`, qui ne rendrait **rien**. Mesuré dans le
   `~/.config/git/config` rendu : l'intégration passe par `[pager] diff/log/show/blame`
   et `[delta] diffFilter`. L'assert de comportement est donc
   `git config --get pager.diff`.

### Deux contre-factuels mesurés, parce que sans eux j'aurais vérifié du vide

- **`programs.ssh.enableDefaultConfig = false`** : avec `true`, le bloc `Host *`
  gagne `AddKeysToAgent`, `Compression`, `ForwardAgent`, `HashKnownHosts`,
  `ServerAliveCountMax`, `ServerAliveInterval` et `UserKnownHostsFile`. Avec le
  `false` d'enginseer il ne reste que les quatre clés déclarées plus `SetEnv`.
  Donc **l'absence de `ForwardAgent`** est ce qui prouve le réglage — pas la
  présence de `ControlMaster`, qui ne distingue pas les deux cas.
- **`historyWidget.command = ""`** : le corps de `config.fish` est **inchangé**
  entre les deux cas, à un chemin de store près. Le réglage ne passe pas par le
  fish rendu mais par `hm-session-vars.fish` :
  `set -gx FZF_CTRL_R_COMMAND ''` côté STC contre `'fzf'` par défaut. **Un assert
  sur `config.fish` n'aurait rien prouvé** ; celui qui prouve est la variable
  d'environnement de la session.

### Structure de `config.fish`, qui contraint la forme des asserts

Mesuré : les alias sont **dans** un bloc `status is-interactive; and begin … end`,
donc un `fish -c` non interactif ne les définit pas. L'`oh-my-posh init` et le
`source` de `hm-session-vars.fish` sont **hors** de ce bloc, donc inconditionnels.
L'assert d'alias au runtime devra passer par un fish interactif, et si ça ne
marche pas, il reste sur le fichier rendu **en disant que le runtime n'est pas
prouvé** — pas un assert de fichier maquillé en assert de comportement.

### Observation produit pour #86, pas corrigée ici

`cogitator/home/enginseer/default.nix` pose `programs.fzf.historyWidget.command`
à **priorité normale** : mesuré en tentant le contre-factuel sans `mkForce`,
l'éval échoue sur `has conflicting definition values`. Un consommateur qui
préfère le Ctrl-R de fzf à celui d'atuin — préférence légitime sur son propre
shell — doit donc poser un `mkForce`. C'est le critère 3 de #86. **Consigné, pas
corrigé** : la décision 5 du plan interdit de toucher `cogitator/` dans ce
chantier, et #86 suit déjà ce motif.

---

<!-- Une ligne par step livré, chaque ruling, chaque mineur différé. -->

## Step 1 (#83) — l'épreuve enginseer et son enregistrement

Un seul commit pour les trois fichiers, même ruling qu'au chantier 1 : l'épreuve
n'est vérifiable qu'une fois l'attribut présent.

**Le mécanisme Home Manager a tenu du premier coup** — l'activation est bien une
unité ordinaire du nœud et `wait_for_unit("home-manager-proving.service")` passe.
Mais **six tours de banc** ont été nécessaires, et aucun n'était un échec du
mécanisme : à chaque fois une de mes prémisses sur *où* un réglage atterrit était
fausse. Chacune lue dans le fichier rendu avant correctif.

1. **Syntaxe Nix, deux fois de suite.** Mes `\''` Python contenaient `''`, qui
   **termine** la chaîne indentée Nix — et le commentaire que j'ai écrit pour
   l'expliquer citait la séquence littéralement, donc cassait aussi. Reformulé
   sans la citer. Leçon réutilisable : deux quotes simples consécutives n'ont
   pas leur place dans un `testScript`, **même en commentaire**.
2. **Assertion amont : `programs.fish.enable` est requis au niveau système** dès
   qu'un utilisateur a fish en shell de connexion, sinon « the fish shell [lacks]
   the basic nix directories in its PATH and might make logging in as that user
   impossible ». **Satisfaite plutôt que muselée** par `ignoreShellProgramCheck`,
   parce que cette épreuve se connecte vraiment. Devient la 4ᵉ concession de banc.
3. **`diffFilter` est sous `[interactive]`, pas sous `[delta]`.** J'avais lu un
   `grep` — qui montrait `[delta]` ligne 9 et `diffFilter` ligne 13 — et attribué
   la clé à la mauvaise section. Lire le fichier l'a réfuté en une commande. Le
   `[delta]` ne porte que `features = "catppuccin-frappe"`.
4. **`programs.direnv.silent` n'écrit pas le mot « silent ».** Il rend
   `[global]` avec `log_filter = "^$"` et `log_format = "-"`. L'assert porte
   maintenant sur la forme observable.
5. **Le pinentry n'est pas dans l'unité systemd.** Il atterrit dans
   `~/.gnupg/gpg-agent.conf` (`pinentry-program …pinentry-curses…/bin/pinentry`) ;
   l'unité rendue ne porte que `GNUPGHOME` et l'`ExecStart`. **Prémisse du plan
   pour le chantier 3 corrigée au passage** : l'assert croisé de #50 se lira dans
   `gpg-agent.conf`, pas dans l'unité.

**Vérification de discrimination de la concession 2**, faite parce qu'ajouter du
fish système pouvait rendre l'assert d'alias creux. Mesuré sur un nœud avec fish
système + Home Manager + l'utilisateur mais **sans cogitator STC** :
`environment.shellAliases` vaut `{l, ll, ls}` et le module fish système en hérite,
tandis que `programs.fish.enable` de HM reste `false` (donc pas de
`~/.config/fish/config.fish`). Donc `type -t cat` rend « function » **seulement**
avec le cogitator. Et ça confirme a posteriori la décision de n'asserter que
`cat`/`cp`/`ping` : **asserter `ll` aurait été vert sans STC.**

Neuf subtests verts, script en **25,07 s**.

## Step 2 (#83) — la doc EN + FR

Quatre endroits : ligne de table de couverture, paragraphe de coût (neuf/douze →
**dix/treize**, avec les 25 s mesurés et la mention des ~40 paquets de la
trousse), l'étape 1 d'« Ajouter une épreuve » qui signale la seconde signature
`{self, inputs}` et pourquoi, et une **nouvelle section « Vérifier un cogitator
Home Manager »** qui porte : le refus argumenté du `nix build` de
`home.activationPackage`, les quatre concessions de banc en table, les **cinq**
candidats corrigés ou écartés par la mesure, le contre-factuel qu'a demandé
`enableDefaultConfig`, et la limite de périmètre « configuration, pas agent
vivant ».

`just docs-parity` vert.
