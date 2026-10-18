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

## Revue de clôture par contexte neuf — zéro Critical, 8 Important, 6 Minor

**Zéro Critical, et c'est mesuré et non argumenté** : le relecteur a bâti un nœud
de référence (Home Manager + fish système + le même utilisateur, sans cogitator
STC) et **fait tourner les neuf subtests dessus** — tous rouges. Dont les deux que
je redoutais : `type -t cat` rend `'file'` et non `'function'`, et
`FZF_CTRL_R_COMMAND` n'y est pas posée (l'intégration `fzf --fish` ne fait que
*lire* la variable, jamais la poser), donc « posée et vide » est bien un état
distinguable. Il a aussi confirmé que `type -t ll` rend `'function'` sur ce nœud
de référence — la décision d'écarter `ll` était donc nécessaire, pas prudente.

Les huit Important sont fondés, les quatre factuels revérifiés par moi avant
acceptation. Deux classes :

**(a) Deux corrections du chantier qui survivaient dans l'en-tête.** J'avais
corrigé `[delta] diffFilter` → `[interactive] diffFilter` et « le pinentry est
dans l'unité » → « dans `gpg-agent.conf` » **dans le corps** du fichier, et laissé
la version fausse dans l'en-tête, à vingt lignes d'intervalle. Le fichier se
contredisait. Leçon : corriger un fait, c'est le corriger *partout* dans le
fichier, et l'en-tête est le premier endroit qu'on lit et le dernier qu'on relit.

**(b) Quatre chiffres ou formulations faux, de ma main :**

1. **« sept alias dont quatre de lsd » → neuf dont six.** Mesuré :
   `grep -c '^    alias '` rend **9** (`cat cp la ll lla llt ls lt ping`), dont
   **6** citant lsd. J'avais oublié `lla` et `llt`. Faux dans cinq endroits. La
   conclusion (n'asserter que `cat`/`cp`/`ping`) ne bouge pas.
2. **« `"fzf"` par défaut » est faux** : `historyWidget.command` a pour défaut
   `null`, et `fzfEnvVars` filtre les `null`, donc le défaut ne rend **aucune**
   variable. Mesuré dans les deux sens (`stc_hasVar = true` valeur `""`,
   `dflt_hasVar = false`). C'est celui que je n'aurais jamais vu seul.
3. **« une vérification sur `core.pager` aurait été un faux vert » est faux** :
   `git config --get core.pager` sort en **rc=1**, donc `machine.succeed` aurait
   rougi. Le mode de défaillance était l'inverse de ce que j'écrivais — et
   l'en-tête du même fichier le disait juste, vingt lignes plus haut.
4. **« Trois concessions de banc » en titre, quatre dans la liste.** Le titre n'a
   pas suivi l'ajout de `programs.fish.enable`.
5. **« les deux épreuves Home Manager »** : il n'y en a qu'une sur cette branche,
   `home-desktop` est le chantier 3. Reformulé en « cette épreuve, comme toute
   future épreuve Home Manager ».

**La divergence non enregistrée qu'il a trouvée, et c'est la plus instructive.**
J'ai écrit « Measured: both options change the closure ». Faux. Le plan avait
mesuré la **paire** conjointement — ce qui est vrai — et j'ai promu l'énoncé en
revendication *par option* sans remesurer. Vérifié : `useGlobalPkgs` seul rend un
`drvPath` d'activation **identique au byte** au défaut (`d8kar8pm…` des deux
côtés) ; seul `useUserPackages` le déplace (`zn9pca3j…`). La *justification* de
`useGlobalPkgs` reste bonne et vérifiée (`useNixpkgsModule = !cfg.useGlobalPkgs`,
donc elle retire bien une seconde instance nixpkgs) — c'est la phrase « mesuré »
qui était fausse. Reformulée, et la justification de `useUserPackages` dit
maintenant que le chemin déterministe sert au **chantier 3** et qu'aucun subtest
ici ne le lit.

Les Minor pris : `~40 paquets` → **31 nommés** (le compte de `home.packages`) ;
« Sept des huit épreuves » → « Huit des dix » (compte périmé déjà sur `main`, que
j'avais laissé en mettant à jour le paragraphe voisin) ; l'unité gpg-agent ne
« porte que GNUPGHOME et ExecStart » (elle porte aussi `ExecReload` et toute une
section `[Unit]`) → ramené à la revendication vraie et suffisante, « elle n'en dit
rien » ; et une nuance d'ordonnancement mesurée par le relecteur, que j'ignorais :
**fish écrit lui-même un `config.fish` de 87 octets à son premier démarrage
interactif**, donc ce chemin peut exister sur un nœud de référence. Mes asserts
lisent tous du *contenu* et jamais la simple existence, donc rien n'est affaibli —
mais la phrase « aucun des chemins lus plus bas n'existe sans le cogitator » était
absolue là où le fait est conditionnel. Reformulée.

**Deux gates manquaient au record, pas à l'exécution** : `just test` (dix
épreuves) et l'identité des `drvPath` après changement n'étaient consignés que
dans mon message, pas ici. Le relecteur les a remesurés lui-même —
`k2mxsivc…`, `2gymzw2p…`, `1xnz47d7…`, identiques au PF-5 — et `just ci` sort en 0.
Consignés maintenant. `nix develop .#docs --command just docs-build` : vert,
90 pages.

Rien dans cette revue ne s'est avéré faux. Les dix affirmations amont qu'elle
avançait ont été vérifiées, quatre par moi avec la commande, les six autres déjà
mesurées pendant le chantier.

---

## Chantier 3 (#50) — pre-flight exécuté le 2026-10-18

Branche `test/proving-home-desktop`, ouverte sur `main` après merge de la PR #93.

**Méthode changée, et c'est la revue du chantier 2 qui l'a enseignée.** Au lieu
de mesurer les options une par une, j'ai **bâti le nœud de référence d'abord**
(Home Manager + le même utilisateur `proving`, sans aucun cogitator STC) et
éprouvé chaque candidat contre lui. C'est strictement mieux : c'est ce que le
relecteur avait fait et qui lui a permis de certifier les neuf subtests d'un
coup.

**Ce que le nœud de référence rend** : les mêmes cinq fichiers qu'au chantier 2
plus les deux `.keep`, et `users.users.proving.packages` ne contient qu'un
`home-manager-path` — Home Manager agrège tout dans une seule dérivation.
**Conséquence immédiate** : l'assert zen-browser doit viser un **binaire** dans
le profil, pas un nom de paquet comme le plan le laissait entendre.

**Ce que `desktop` seul ajoute** (donc ce qui discrimine) :
`kitty/kitty.conf`, `systemd/user/app-com.mitchellh.ghostty.service` et son
`.d/overrides.conf`, et `.local/share/dbus-1/services`.

### Deux prémisses du plan corrigées par la mesure

1. **Le binaire de zen-browser s'appelle `zen-beta`, pas `zen`.** Le cogitator
   importe `inputs.zen-browser.homeModules.beta`. Mesuré en listant le `bin/` du
   `home-manager-path` construit. Asserter `zen` aurait été rouge.
2. **Les polices Nerd de la relique kitty** atterrissent sous
   `share/fonts/truetype/NerdFonts/{JetBrainsMono,Inconsolata,Iosevka,BitstromWera,…}`.
   C'est **la seule option propre à STC des trois reliques** (`kitty.fonts.enable`,
   défaut `true`) — les deux autres ne font que poser `programs.<x>.enable = true`.
   Elle méritait d'être relevée : activer le cogitator installe sept paquets de
   polices, ce qui est du poids de clôture que le consommateur doit connaître.

### Ruling — l'assert « inerte » quitte la VM

La décision 4 du plan prévoyait, sur le nœud `desktop` seul, un assert
« **aucune** unité `gpg-agent` utilisateur » pour prouver le mot « inert » du
commentaire de `cogitator/home/desktop.nix`.

**Mesuré : ça ne discrimine pas.** Le nœud de référence n'a pas d'unité
`gpg-agent` non plus (`services.gpg-agent.enable = false` sans aucun cogitator).
L'assert serait vert quoi que fasse STC — exactement la classe que la méthode dit
de supprimer plutôt que d'affaiblir.

L'inertie est une propriété d'**évaluation**, pas de runtime : `desktop` seul pose
`services.gpg-agent.pinentry.package = pinentry-qt` (mesuré) alors que
`services.gpg-agent.enable` vaut `false`, donc rien ne la consomme et aucun
`gpg-agent.conf` n'est rendu. La lire depuis la VM demanderait d'interpoler la
valeur de l'option depuis la *même* évaluation — une tautologie.

**Donc : assert retiré de la VM, fait consigné ici et en doc.** Même traitement
que le cas négatif de `docker-server` (« a negative case cannot live in a
nixosTest, verify by `nix eval` ») et que `boot.zfs.devNodes` au chantier 1.

### Les deux nœuds sont gardés, et chacun gagne son boot

- **`desktop`** — les trois reliques **en isolation** : `kitty.conf`, l'unité
  ghostty et son `overrides.conf`, les binaires `zen-beta`/`gimp`/`vlc` dans
  `/etc/profiles/per-user/proving/bin`, et les polices Nerd. Isolé d'enginseer à
  dessein : une épreuve nommée `home-desktop` qui rougirait à cause d'enginseer
  serait un mauvais diagnostic.
- **`composed`** — desktop **+** enginseer, pour la seule revendication croisée :
  le `mkForce pinentry-qt` de desktop gagne contre le `mkDefault pinentry-curses`
  d'enginseer. Lu dans `~/.gnupg/gpg-agent.conf` — **et non dans l'unité
  systemd**, prémisse du plan déjà corrigée au chantier 2.

Le nœud `composed` reproduit le nœud du chantier 2 au détail près (utilisateur
`proving`, `stateVersion` 25.11, `useGlobalPkgs`/`useUserPackages`, fish système),
sinon la comparaison avec le `pinentry-curses` mesuré là-bas ne vaudrait rien.
Le nœud `desktop` seul **ne pose pas** fish : le profil ne revendique aucun shell,
et poser fish y entraînerait l'assertion amont de `programs.fish.enable` pour rien.

## Step 3 (#50) — l'épreuve home-desktop et son enregistrement

Un seul commit pour les trois fichiers, même ruling qu'aux deux chantiers
précédents.

Le mécanisme acquis au chantier 2 a tenu sans un seul ajustement. **Un seul tour
de banc rouge**, contre six au chantier précédent — l'écart vient directement de
la méthode changée : bâtir le nœud de référence d'abord, puis éprouver chaque
candidat contre lui.

**Le tour rouge, et ce qu'il a appris :** l'assert des polices visait
`/etc/profiles/per-user/proving/share/fonts/truetype/NerdFonts/JetBrainsMono`,
chemin que j'avais relevé sur le `home-manager-path` construit. Rouge. Cause lue
avant correctif : `environment.pathsToLink` **ne contient aucune entrée
`/share/fonts`**, donc le profil par utilisateur ne lie jamais les polices — j'avais
mesuré la bonne dérivation et conclu sur la mauvaise. Les polices sont dans le
`home-manager-path`, et c'est
`~/.config/fontconfig/conf.d/10-hm-fonts.conf` qui le désigne (lu : il liste le
`share/fonts` de cette dérivation **et** celui du profil par utilisateur, ce
dernier vide).

L'assert est devenu **meilleur** que celui que j'avais prévu, pas juste
réparé : `su - proving -c 'fc-list : family'` doit montrer
`JetBrainsMono Nerd Font` et `Iosevka Nerd Font`. C'est la question de
comportement — *la session trouve-t-elle ces polices* — qui est à la fois la
bonne et la seule à avoir une réponse vraie. Et elle couvre toute la chaîne
relique → fontconfig → session.

Huit subtests verts sur deux nœuds, script en **23,04 s**.

Écart au plan consigné : le nœud `desktop` seul **ne pose pas** fish là où le
nœud `composed` le pose. Raison : le profil desktop ne revendique aucun shell, et
poser fish y déclencherait l'assertion amont de `programs.fish.enable` pour rien.
Le nœud `composed`, lui, reproduit le nœud du chantier 2 au détail près — sinon
la comparaison de son pinentry avec le `pinentry-curses` mesuré là-bas ne
vaudrait rien. Les concessions de banc partagées sont factorisées dans un `let`
pour que les deux nœuds ne puissent pas dériver.

## Step 4 (#50) — la doc EN + FR

Ligne de table de couverture ; paragraphe de coût (dix/treize →
**onze/quinze**, `home-desktop` nommée comme troisième épreuve à deux nœuds, et
GIMP/VLC/Zen Browser ajoutés aux clôtures citées) ; une sous-section
« Deux nœuds, et la revendication qui réclamait un contre-factuel impossible »
qui porte le ruling sur l'assert « inerte », le `zen-beta` et l'histoire des
polices ; et deux comptes remis à jour que l'ajout déplaçait — « les deux
épreuves Home Manager » (il y en a deux maintenant, la formulation du chantier 2
disait « cette épreuve ») et « dix des onze épreuves laissent le pilote
synthétiser un nœud ».

`just docs-parity` vert.
