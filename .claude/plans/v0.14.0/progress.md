# Ledger — plan: .claude/plans/v0.14.0/plan.md

Pre-flight: les quatre paires proving → registre (1.1→1.2, 2.1→2.2, 3.2→3.3,
4.2→4.3) exportent toutes la même forme `{self}: {name; nodes; testScript;}` et
sont toutes importées par `import ./<nom>.nix {inherit self;}` — contrat vérifié
contre les trois provings existants. Paire 3.1→3.3 : le nom `pkgs-unfree` est
celui du `let` du registre, écrit à l'identique dans la ligne `gaming` (et
emprunté à `forge/default.nix`, qui l'épelle pareil). Paire 4.1→4.2 : le nœud
dreadnought ne doit porter **aucune** définition de
`systemd.services."serial-getty@ttyS0"` — c'est tout l'objet du Step 4.1. Aucune
option nouvelle, aucun renommage : Gate 3 sans objet.

Ruling (avant toute ligne de code) : les quatre cogitators ont été sondés en
évaluation, chacun dans un `runNixOSTest` jetable, **avant** d'écrire le plan.
Deux surprises, qui ont changé le plan :

1. `cogitator-gaming` n'évalue pas du tout — `steam` est unfree et le `pkgs` de
   `perSystem` ne l'autorise pas. Les deux voies « locales » sont mesurées
   fermées : `nixpkgs.config.allowUnfree` dans le nœud donne
   `nixpkgs.config is set to read-only`, et `node.pkgs` est déjà défini par
   `runNixOSTest` lui-même (`node.pkgs is defined multiple times`). Seul
   `pkgsUnfree.testers.runNixOSTest` passe — c'est exactement le patron
   `pkgs-unfree` que `forge/default.nix` emploie pour Terraform (BSL), scopé à
   la ligne qui en a besoin.
2. `cogitator-dreadnought` échoue deux fois de suite : d'abord
   `ZFS requires networking.hostId to be set` (le nœud le pose, comme les
   schematics), ensuite un conflit dur sur `systemd.services."serial-getty@ttyS0"`
   — `relics/nixos/aws.nix:82` pose `true` à priorité normale, le socle de test
   pose `false` à la même priorité. Conséquence qui dépasse le test : **aucun
   consommateur de la relique AWS ne peut désactiver ce getty sans `mkForce`**.

Ruling (arbitré avec l'utilisateur, 2026-10-17) : la cause racine du point 2 est
la priorité dans la relique, pas le test. On corrige `relics/nixos/aws.nix` en
`lib.mkDefault true` et le proving ne porte aucun override. Un `mkForce` dans le
test aurait masqué le défaut. Garde-fou : la valeur doit rester `true` pour un
consommateur qui ne change rien, et les `drvPath` des schematics doivent être
identiques avant/après — c'est la vérification du Step 4.1.

Ruling (arbitré avec l'utilisateur, 2026-10-17) : un seul plan et un seul ledger
pour les quatre chantiers, mais une branche, une PR et un merge par issue. Les
quatre provings partagent une méthode unique et un même jeu de prémisses
mesurées ; quatre plan files les auraient recopiées quatre fois. Ce qui reste
interdit (mélanger deux issues dans une branche) ne l'est pas.

Ruling (portée, écrit avant le code pour ne pas être découvert comme un échec) :
mesuré que le module qemu-vm remplace `fileSystems` **et**
`boot.loader.grub.device` dans le nœud dreadnought (`/` + `/nix/.ro-store` +
`/nix/.rw-store` + `/nix/store` + `/tmp/shared` + `/tmp/xchg`, et
`/dev/disk/by-id/virtio-root`), et que le socle de test désactive `timesyncd` et
les noms d'interfaces prévisibles. Donc import de pool, montage des datasets,
device EBS, endpoint NTP AWS et résolveurs Quad9 sont hors de portée du proving —
pour des raisons de framework, pas de code. Ils vont en note de portée, avec
renvoi au vrai banc (le qcow2 de `schematics/local-vm`, celui qui a servi à #70).
Un assert sur une valeur posée par le framework ne prouve rien : on ne les écrit
pas.

---

## Steps

### Chantier 1 — #48, proving `vm` (branche `test/proving-vm`)

- **Step 1.1 — `provings/vm.nix`.** Deux nœuds (`machine` aux défauts,
  `dockervm` avec `docker.enable = true`), 7 subtests. Valeurs attendues toutes
  mesurées avant d'être écrites : shell `fish-4.9.3`, groupes `["wheel"]` puis
  `["wheel" "docker"]`, `OnCalendar=weekly`, `--delete-older-than 5d`,
  `experimental-features = nix-command flakes`.
  Vérif : `nix build .#legacyPackages.x86_64-linux.provings.vm -L` → `exit=0`,
  script de test en 27,7 s.
- **Step 1.2 — registre + recette.** `vm` dans `provings/default.nix` **et** dans
  la recette `test` du `Justfile` (la deuxième moitié est celle qu'on oublie, et
  sans elle le vert est faux).
- **Step 5 (part 1) — doc EN + FR.** Ligne de couverture `vm`, et correction de
  la procédure « Adding a proving » : elle listait 3 étapes et sautait la recette
  `Justfile`, que `CLAUDE.md` et le Gate 5 exigent. `just docs-parity` ✅.

Ruling (trouvé au premier build, cause racine avant correctif) : l'assert
`machine.wait_for_unit("linger-users.service")` ne pouvait structurellement pas
passer. Mesuré dans `nixos/modules/config/users-groups.nix:905-951` : l'unité est
un `Type = "oneshot"` **sans** `RemainAfterExit`, tirée par `multi-user.target` —
donc au moment où le script interroge, elle a déjà fini et elle est
`inactive (dead)`, état que `wait_for_unit` refuse par définition. Ce n'était pas
un défaut du produit mais une mauvaise primitive d'attente de ma part.
Remplacé par `systemctl show -p Result --value linger-users.service` → `success`
plus la présence du marqueur `/var/lib/systemd/linger/admin`. Première règle
appliquée : une seule tentative, après diagnostic, pas trois essais.

**Correction de la ligne ci-dessus (revue de clôture, mesurée) :** j'avais écrit
que la paire prouvait « que le mécanisme a tourné *et* qu'il a laissé sa trace ».
C'est faux, et la revue l'a attrapé. Mesuré sur un systemd vivant :
`systemctl show -p Result --value definitely-not-a-real-unit.service` rend
`success` avec un code de retour **0** (`LoadState=not-found`). La propriété
`Result` ne discrimine donc ni l'existence ni l'exécution : le seul assert
porteur du couple est le marqueur. `LoadState` (`loaded`) serait la bonne
propriété. À ne pas réutiliser tel quel dans les chantiers 2 à 4. Le correctif de
code est classé Minor par la revue, donc laissé à l'arbitrage de l'utilisateur
(règle *Closing review* : les Minor ne rentrent pas dans la passe de correction).

Note de méthode (coûtée une fois, à ne pas repayer) : `nix build` sur un flake
git refuse un fichier **non suivi** (`Path 'provings/vm.nix' … is not tracked by
Git`). Un `git add` suffit — c'est aussi ce qui permet de vérifier avant de
commiter, donc avant toute commande signée.

**Passe de correction après revue de clôture (contexte neuf, subagent).** Un
Important, huit Minor. Seul l'Important est corrigé ici, conformément à la règle
*Closing review* (« Minor goes to the ledger and to the closing message as a
deferred item. It does not enter the fix pass — the user decides »).

- **Important retenu :** `authorizedKeys` est la **seule** option du profil qui
  ouvre l'accès distant, et le proving ne la touchait pas — mesuré
  `users.users.admin.openssh.authorizedKeys.keys == []` sur les deux nœuds. Les
  deux asserts en place (`wait_for_unit("sshd.service")` +
  `wait_for_open_port(22)`) ne prouvaient qu'un socket en écoute. Conséquence :
  retirer `cogitator/nixos/vm.nix:100` rendait toute VM consommatrice injoignable
  **sans** faire rougir le proving, et la ligne de doc (« sshd répond sur 22 »)
  se lisait comme « l'accès distant marche ».
  Corrigé par le patron déjà présent dans `provings/hardening.nix` : paire
  snakeoil de nixpkgs, clé publique passée par `stc.cogitator.vm.authorizedKeys`,
  privée copiée en `0600` dans `/etc/proving-ssh-key`, puis un vrai
  `ssh -n … admin@127.0.0.1 id -un` dont on compare la sortie à `admin`.
  **Reproduction vue dans les deux sens**, c'est ce qui rend l'assert crédible :
  avec la ligne 100 retirée, `nix build …provings.vm` → `exit=1` sur
  `test -s /etc/ssh/authorized_keys.d/admin` ; ligne restaurée → `exit=0`,
  script en 28,8 s.
  Ligne de couverture EN + FR recalée sur la revendication réelle (une clé
  déclarée authentifie, pas « le port répond »).

**Minor arbitrés par l'utilisateur (2026-10-17).** Il prend le groupe « qualité
des asserts » (4 des 8), laisse les autres au report :

- *Pris.* `Result` → `LoadState` (`loaded`), puisque `Result` ne discrimine rien.
  `wait_until_succeeds` sur le marqueur de linger : mesuré que l'unité ne porte
  **aucun** `Before=` vers `multi-user.target`, donc systemd peut déclarer la
  cible active pendant que `enable-linger` tourne encore — c'est la classe de
  course que les autres provings évitent déjà. Suppression du pipeline
  `su … | grep -q .`, qui rendait le code de `grep` et non celui de `su` : on lit
  la valeur de `$FISH_VERSION` et on exige qu'elle commence par un chiffre.
  `experimental-features` vérifié par **appartenance** et non par égalité de
  chaîne : un ajout en amont rougissait pour une raison étrangère au profil.
  Vérif : proving vert, 7 subtests, script en 29,2 s ; `just ci` et `just test`
  à 0.
- *Reportés.* (a) Couverture des options : le script code `admin` en dur à cinq
  endroits, donc un module qui ignorerait `cfg.username` resterait vert ; idem
  pour `linger = false` et `nix.gc.enable = false`, jamais exercés. Un second
  nœud « toutes options hors de leur défaut » fermerait les trois à coût nul.
  (b) En-tête du proving : la note de portée sur les montages est recopiée de
  `hardening.nix` alors que `cogitator/nixos/vm.nix` ne déclare aucun
  `fileSystems` — elle fait croire à un durcissement volontairement non testé ; et
  l'en-tête annonce « les quatre choses » pour 7 subtests.

Deux écarts au plan, relevés par la revue, tous deux assumés : le nœud opt-in
attend `docker.service` et non `docker.socket` comme écrit au Step 1.1 (mesuré
`enableOnBoot = true`, donc équivalent aujourd'hui ; `docker info` qui suit est
l'assert porteur de toute façon), et le point 3 du Step 5 (l'étape `Justfile`
manquante dans la procédure doc) est parti avec ce chantier au lieu du dernier —
il corrigeait une page que ce chantier venait de suivre, l'y laisser aurait été
documenter un piège connu.

### Chantier 2 — #49, proving `plasma` (branche `test/proving-plasma`)

Méthode changée après la revue du chantier 1, et c'est le gain le plus net du
lot : **chaque valeur candidate a été mesurée sur un nœud nu *et* sur le nœud
plasma**, pour séparer ce que la relique produit de ce que le framework pose
déjà. Résultat immédiat : deux asserts prévus étaient vacants et n'ont pas été
écrits — `services.pulseaudio.enable` et `services.xserver.enable` valent **déjà**
`false` sur un nœud nu, donc « PulseAudio coupé » et « pas de serveur X »
auraient été verts quoi que fasse STC. `services.tumbler` écarté pour une autre
raison : aucune unité systemd (activation D-Bus seule), rien à lire sur disque.

- **Step 2.1 — `provings/plasma.nix`.** 5 subtests. Le plus porteur est mesuré
  comme tel : avec la relique Pipewire **seule**,
  `systemd.user.services.wireplumber.wantedBy == ["pipewire.service"]` (amont) ;
  le cogitator plasma y ajoute `"default.target"`. Donc
  `/etc/systemd/user/default.target.wants/wireplumber.service` existe **à cause
  de la seule ligne de décision STC du fichier** — retirez-la, le lien disparaît.
  Les autres : SDDM en Wayland (`DisplayServer=wayland`,
  `DefaultSession=plasma.desktop`, greeter en `kwin_wayland`), le portail XDG
  (`default=*`, fichier qui n'existe pas sans la ligne de la relique), rtkit
  (`false` en amont), les unités utilisateur Pipewire/WirePlumber, et
  `gvfs-daemon.service` — côté **utilisateur** et non système, vérifié dans
  `lib/systemd/user/` du paquet.
- **Step 2.2 — registre + recette.** Les deux moitiés.

Ruling (échec vu au premier build, cause racine avant correctif) : l'assert
`test -e /run/current-system/sw/share/wayland-sessions/plasma.desktop` était
rouge. Cause : j'avais **inféré** ce chemin de la présence de
`plasma-workspace` dans `environment.systemPackages` au lieu de le mesurer dans
la VM. Les sessions ne vivent pas dans le profil système mais dans une dérivation
synthétique `desktops` que le module display-manager fabrique depuis
`sessionPackages` et que `sddm.conf` désigne. Corrigé en **dérivant le répertoire
de la configuration sous test** (lecture du `SessionDir=` rendu, puis
`test -e <dir>/plasma.desktop`) : l'assert prouve désormais l'endroit où le
display manager va réellement chercher, ce qu'un chemin deviné ne faisait pas.
Leçon à reporter aux chantiers 3 et 4 : une valeur lue par un assert se mesure
**dans la VM** ou se dérive de la configuration, jamais de l'intuition.
Vérif : proving vert, 5 subtests, script en 25,4 s.

**Passe de correction après revue de clôture du chantier 2.** Six Important,
sept Minor. La revue a poussé la méthode un cran plus loin que moi : j'avais
comparé les **valeurs d'options** sur un nœud nu, elle a comparé aussi sur un
nœud portant le module `plasma6` de nixpkgs **sans STC**. Ce troisième point de
comparaison change le verdict de plusieurs asserts.

- **I1 — deux asserts d'unités utilisateur étaient vacants.** Mesuré :
  `nixos/modules/services/desktop-managers/plasma6.nix` pose
  `services.pipewire.enable = mkDefault true`. Donc avec la relique Pipewire de
  STC retirée du cogitator, `pipewire.socket` et `wireplumber.service` existent
  encore. Retirés : ma règle du chantier 2 s'appliquait aux valeurs d'options, pas
  aux fichiers d'unités, et c'est là que les deux survivaient.
- **I2 — l'assert Pipewire qui discrimine vraiment, ajouté.**
  `alsa.support32Bit` est `false` en amont, `true` avec la relique, et atterrit
  dans `/etc/alsa/conf.d/49-pipewire-modules.conf`. Mesuré dans les deux sens :
  relique coupée, le fichier existe **sans** ligne `libs.32Bit`. C'est la
  revendication « ALSA 32 bits » sur laquelle repose tout l'argument Steam/Wine du
  cogitator, et elle n'était pas testée.
- **I3 — mon affirmation sur tumbler était fausse, et publiée dans les deux
  pages de doc.** J'avais écrit qu'il « ne livre aucune unité systemd, donc rien
  à lire sur disque ». Les deux moitiés sont fausses :
  `tumbler-4.20.2/lib/systemd/user/tumblerd.service` existe, et le fichier
  d'activation D-Bus atterrit dans
  `/run/current-system/sw/share/dbus-1/services/org.xfce.Tumbler.Thumbnailer1.service`
  (absent sur un nœud nu, `services.tumbler.enable = false`). Un assert
  discriminant et gratuit avait donc été jeté sur une prémisse fausse. Assert
  ajouté, les deux pages corrigées.
- **I5 — l'assert sur l'unité du portail était vacant** (`xdg.portal.enable` est
  posé par le module plasma6 amont). Retiré ; `default=*` reste, lui est porteur
  (sans la ligne de la relique le fichier n'existe pas du tout).
- **I6 — les deux réglages documentés de la relique n'étaient pas couverts.**
  `keyboardLayout` et `sddmTheme` sont les seules options tunables du fichier, et
  le nœud les prenait à leur défaut. Ils sont maintenant posés hors défaut sur le
  **nœud existant** — couverture gagnée à coût nul, zéro VM de plus.

Ruling (I4 — un vrai défaut produit, trouvé par la revue, corrigé sous le même
arbitrage que la décision 4) : `relics/nixos/plasma6.nix` épinglait
`services.xserver.enable = false` à **priorité normale**, ce qui rendait sa propre
option documentée `wayland = false` **inutilisable**. Reproduit dans les deux
sens avant de toucher à la ligne :

- `stc.relics.plasma6.wayland = false` seul → `Failed assertions: - SDDM requires
  either services.xserver.enable or services.displayManager.sddm.wayland.enable
  to be true`.
- La seule échappatoire, `services.xserver.enable = true`, était impossible :
  `has conflicting definition values: - In relics/nixos/plasma6.nix: false`.

Donc l'option que la doc présentait comme « le repli pour GPU ancien »
n'était atteignable par aucun moyen hors `mkForce`. Correction : `lib.mkDefault
false`, même ruling que le getty série d'`aws.nix` — la cause racine est la
priorité, pas le test. Après : `wayland = false` + `services.xserver.enable =
true` évalue et rend `DisplayServer=x11`. Chemin par défaut **inchangé**, prouvé
par identité de `drvPath` (provings `workstation` et `plasma`, qcow2 de
`local-vm` : les trois identiques avant/après). La description de l'option et les
deux pages de relique disent maintenant que le repli demande **deux** réglages —
c'était la deuxième moitié du mensonge.

**Troisième occurrence du même défaut, non corrigée ici (à arbitrer).** La revue
signale que `cogitator/nixos/plasma.nix:30` pose `stc.relics.pipewire.enable =
true` à priorité normale alors que son commentaire promet « override only to
disable » — surcharger exige un `mkForce`. Avec `aws.nix` (décision 4) et
`plasma6.nix` (I4), ça fait trois endroits où STC épingle une valeur à priorité
normale en documentant qu'elle est surchargeable. Le motif mérite un audit à part,
pas un troisième correctif en passant.

Minor reportés : la ligne de couverture omettait le subtest gvfs (corrigée au
passage), le chemin `/etc/sddm.conf.d/00-nixos.conf` est codé en dur (nom choisi
par l'amont, dérivable), `len(session_dirs) == 1` n'est vrai que parce que
`xserver` est coupé, et l'en-tête du proving attribuait les défauts `false` au
« framework de test » alors qu'ils viennent de nixpkgs (corrigé en réécrivant
l'en-tête).

### Chantier 3 — #44, proving `gaming` (branche `test/proving-gaming`)

Méthode portée à **quatre** nœuds (nu / `programs.steam` seul / relique AMD
seule / cogitator complet), parce que ce cogitator a trois moitiés qui se
recouvrent. Le résultat a invalidé un assert du plan avant qu'il soit écrit :

**Ruling — `/run/opengl-driver-32` ne prouve pas la relique AMD.** Mesuré :
`programs.steam.enable` **seul** pose déjà `hardware.graphics.enable32Bit`
(et `hardware.steam-hardware.enable`). Le Step 3.2 du plan citait les pilotes
32 bits comme « la revendication `enable32Bit` de la relique AMD, celle dont
Proton dépend » — c'est faux : les deux moitiés du cogitator la demandent, donc
l'assert prouve la composition, pas la relique. Il est gardé, mais son
commentaire le dit, pour qu'aucun lecteur ne crédite la relique.

Ce qui discrimine la relique AMD, et que le plan ne prévoyait pas :
`hardware.graphics.extraPackages` est **vide sur un nœud nu et sur un nœud Steam
seul**, et porte `libvdpau` + `libva-vdpau-driver` avec la relique. L'assert
écrit est donc `test -e /run/opengl-driver/lib/dri/vdpau_drv_video.so`, le
fichier que ce paquet pose dans l'arbre fusionné (chemin relevé dans le paquet,
pas deviné — leçon du chantier 2).

- **Step 3.1 — instance `pkgs-unfree`.** Les deux voies locales re-vérifiées
  fermées, et le commentaire du registre les cite avec leurs messages d'erreur
  exacts, pour que personne ne les retente. **Innocuité prouvée** : les cinq
  provings existants gardent un `drvPath` identique avec l'instance en place
  (`hardening`, `docker-server`, `workstation`, `vm`, `plasma`).
- **Step 3.2 — `provings/gaming.nix`.** 6 subtests, deux nœuds. Le second
  (`remoteplay`) existe parce que `steam.remotePlay` est la **seule** option
  propre du cogitator : sans lui elle serait non testée, et l'assert « fermé par
  défaut » n'aurait pas de contrepartie. Bornes mesurées respectées :
  `27031:27035` en UDP, aucun range TCP — écrire `27036` (le nombre que cite la
  doc de Steam) aurait rougi pour une raison étrangère à STC.
- **Step 3.3 — registre + recette**, la ligne `gaming` étant la seule bâtie
  depuis `pkgs-unfree`.
- **Doc EN + FR** : ligne de couverture, plus une section « paquets unfree dans
  une épreuve » qui donne les deux messages d'erreur et le patron retenu — c'est
  un fait structurel du registre, pas un détail de ce chantier.

Vérif : proving vert **du premier coup**, 6 subtests, script en 22,9 s.

**Passe de correction après revue de clôture du chantier 3.** Quatre Important,
quatre Minor. Deux corrections comptent plus que les autres.

- **I2 — j'ai publié un fait faux pour la deuxième fois, et il était vérifiable
  d'une commande.** Ma ligne de doc disait que `steam.remotePlay` ouvre
  « exactement UDP 27031-27035 », et mon commentaire dans le proving prévenait
  qu'écrire `27036` rougirait « pour une raison étrangère à STC ». Mesuré :
  `allowedUDPPortRanges = [{from=27031;to=27035;}]`, **plus**
  `allowedUDPPorts = [10400 10401 27036]`, **plus**
  `allowedTCPPorts = [27036 27037]`. Donc six ports de plus, dont trois en TCP,
  et `27036` est précisément ouvert — mon avertissement était à l'envers. Ce qui
  m'a trompé : au chantier 2 j'avais relevé `allowedTCPPortRanges = []` et j'ai
  lu « aucun TCP » au lieu de « aucune *plage* TCP ». Leçon : quand une mesure
  rend une liste vide, vérifier qu'on a interrogé la bonne option avant d'en
  tirer une négation. Corrigé : assert TCP ajouté (`27037`, TCP-only en amont,
  donc c'est lui qui prouve la moitié que je niais), asserts par ligne et non par
  blob, et les deux pages de doc réécrites.
- **I1 — le subtest « with its hardware rules » n'assertait aucune règle
  matérielle**, et son second assert (`steam-run`) était un doublon du premier :
  les deux paquets viennent de la même liste `systemPackages`, aucune
  configuration n'a l'un sans l'autre. Le plan demandait les règles udev
  (Step 3.2) et je les avais laissées tomber sans ruling. Corrigé :
  `test -e /etc/udev/rules.d/60-steam-input.rules`, chemin relevé dans
  `steam-devices-udev-rules` (pas deviné).
- **I3 — le subtest des pilotes 32 bits ne peut être rougi par aucun changement
  STC**, puisque le subtest précédent prouve déjà que `programs.steam` est actif
  et que ça suffit à poser `enable32Bit`. Mon ruling précédent lui faisait encore
  dire trop (« prouve que la composition boote avec les pilotes 32 bits »).
  Gardé, mais renommé et commenté comme ce qu'il est : une **sentinelle amont**,
  utile si nixpkgs casse Proton pour tous les hôtes du profil, pas un détecteur
  de régression STC.
- **I4 — trois revendications non couvertes, aucune exclue honnêtement.**
  `pulse.enable` (« compat PulseAudio », troisième revendication de l'en-tête de
  la relique Pipewire) **discrimine ici** — contrairement au chantier 2 où le
  module plasma6 l'allume — donc assert ajouté. `amdGpu.initrd` et
  `hardening.filesystem.gaming` sont maintenant dans un paragraphe « ce que ce
  proving ne vérifie pas, et pourquoi » de l'en-tête : le second n'est **pas
  couvrable** (il retire `noexec` de `fileSystems`, que le module qemu-vm
  remplace en bloc), et c'est précisément le footgun que l'en-tête du cogitator
  signale — un lecteur de la ligne de couverture n'avait aucun moyen de
  l'apprendre.

Minor reportés ou traités au passage : asserts de pare-feu passés par ligne (M5),
fragilité du rendu `iptables` face à nftables dite en commentaire (M6),
dépendance au chemin amont `libva-vdpau-driver` notée (M7), et surtout **M8 —
la preuve d'innocuité de l'instance unfree par identité de `drvPath` est quasi
tautologique** (`pkgs-unfree` est une liaison paresseuse que Nix ne force jamais
pour les autres provings). Le vrai périmètre est maintenant écrit en doc : la
clôture **entière** du nœud gaming est évaluée en `allowUnfree`, donc une relique
qui tirerait plus tard un firmware unfree passerait en silence dans cette seule
épreuve. L'instance cantonne par sortie, pas par paquet.

Écart au plan, non consigné à l'époque et relevé par la revue : les Steps 3.1 et
3.3 ont été fusionnés en un commit. Scinder comme le plan le disait aurait **cassé
`just ci`** — `deadnix` signale la liaison `pkgs-unfree` non utilisée tant que la
ligne `gaming` n'existe pas.

### Chantier 4 — #45, proving `dreadnought` (branche `test/proving-dreadnought`)

- **Step 4.1 — `mkDefault` sur le getty série d'`aws.nix`, livré avec sa preuve.**
  Valeur conservée : `aws-ami` rend toujours `true`. Innocuité : les **trois**
  schematics (`awsImage`, `qcow2`, `toplevel` de dreadnought) gardent un
  `drvPath` identique au bit. Le commentaire de la relique dit pourquoi, et
  interdit explicitement de « simplifier » en `true` nu.

**Ruling — décision 6 tranchée par le build, et dans le bon sens.** Le plan
prévoyait que l'échec du rollback d'impermanence dans l'initrd pourrait bloquer
le boot, et prévoyait une réduction de portée dans ce cas. Mesuré : **le boot
n'est pas bloqué.** L'unité est tirée par `Wants` et non `Requires`, donc
l'initrd atteint sa cible malgré l'échec et le système monte. Aucune réduction de
portée n'a été nécessaire.

**Ruling — l'ensemble des unités en échec est borné, pas épinglé.** Première
version de l'assert : `systemctl is-system-running --wait`, rouge — le système est
`degraded`, pas `running`, ce qui est l'état honnête ici. Deuxième version :
épingler l'ensemble à `{stc-grow-pool.service}`, ce qu'une **sonde** avait mesuré.
Rouge aussi : le lancement suivant rendait `{stc-grow-pool.service,
zfs-rollback.service}`. Même configuration, deux résultats — `zfs-rollback` tourne
dans l'**initrd**, et le fait que son échec soit encore listé après le switch-root
varie. Donc l'assert **borne** l'ensemble aux deux unités dépendantes du pool et
exige la présence de `stc-grow-pool.service` : il attrape toujours la régression
qui compte (une *autre* unité qui échoue) sans être instable pour une raison
interne à systemd. Épingler aurait produit un proving rouge au hasard, ce qui est
pire qu'un assert large.

- **Step 4.2 — `provings/dreadnought.nix`.** 6 subtests. Discrimination mesurée
  nœud nu contre nœud dreadnought, ce qui a de nouveau écarté un assert prévu :
  `services.udisks2.enable` vaut **déjà `false`** sur un nœud nu, donc « udisks2
  absent » ne distingue pas la relique AWS. Non écrit, et dit en doc.
  `kernel.kptr_restrict` vaut 1 sur un nœud nu contre 2 ici — il discrimine, lui.
  Le noyau ZFS épinglé (6.12.111 contre 6.18.53 sur un nœud nu) est prouvé par un
  `modprobe zfs` réel, pas par une comparaison de version.
- **Step 4.3 — registre + recette.**
- **Step 5 points 3 et 4 — soldés.** Le coût de `just test` est écrit avec ses
  chiffres : sept épreuves, **neuf boots de VM** (`vm` et `gaming` ont deux nœuds),
  KDE deux fois, Steam une fois. Dit explicitement parce qu'une recette trop
  lourde à lancer est un gate qui cesse discrètement d'en être un.

Note de méthode, payée une fois : mon script Python a vidé `provings/dreadnought.nix`
en imbriquant une lecture du fichier dans un `open(path, "w")` — l'ouverture en
écriture tronque **avant** que la lecture s'exécute. Fichier réécrit en entier.
Ne jamais lire et écrire le même chemin dans la même expression.

**Passe de correction après revue de clôture du chantier 4.** Huit Important,
huit Minor, aucun Critical — la revue la plus sévère du lot, et la plus utile.

- **I1 — troisième fait faux publié de ma part, et le pire des trois parce qu'il
  retournait exactement son propre argument.** J'avais écrit que « le débit est ce
  qui discrimine : le socle passe un `console=ttyS0` nu de son côté ». Mesuré :
  `virtualisation.qemu.consoles = ["ttyS0,115200n8" "tty0"]` sur un nœud **nu**,
  donc c'est le socle qui pose la chaîne complète, débit compris. Retirer
  `console=ttyS0,115200n8` de la relique AWS laissait le proving vert. Conséquence
  nette : **la revendication « console série » de la relique n'a aucune
  couverture** (le getty est coupé, le paramètre vient du socle), et le fichier
  affirmait le contraire. Assert réduit aux deux paramètres qui discriminent, et
  l'absence de couverture est maintenant écrite deux fois — en tête du proving et
  en doc.
- **I2 — mon ruling « borner plutôt qu'épingler » était le choix faible.** Le
  déterminisme était à un champ de distance : la colonne 2 de la commande que
  l'assert parse déjà. Mesuré, `zfs-rollback` n'a **pas de fragment** dans le
  système booté (`LoadState=not-found`), d'où la variance ; filtrer sur `loaded`
  épingle l'ensemble à `{stc-grow-pool.service}` *et* reste stable. Ce que mon
  ensemble borné cachait : il restait vert si une vraie unité du système booté
  nommée `zfs-rollback.service` apparaissait et échouait.
- **I4 — la trouvaille la plus utile du lot.** `environment.persistence` ne passe
  **pas** par `fileSystems` : il produit des bind-mounts systemd, que qemu-vm ne
  touche pas. Donc le contrat central de la relique d'impermanence (« si ce n'est
  pas listé, c'est perdu ») **est** observable ici, et ma note de portée
  détournait le lecteur en rangeant `/persist` avec les montages remplacés.
  Mesuré sur le nœud : `/var/log`, `/var/lib/nixos`, `/etc/machine-id` montés, et
  en posant `impermanence.extraDirectories = ["/var/lib/stc-proving"]` le montage
  apparaît — donc l'option du cogitator traverse de bout en bout, à coût VM nul.
  Subtest ajouté.
  **Correction à la revue sur ce point :** elle affirmait que les quatre
  bind-mounts `/etc/ssh/ssh_host_*` « finissent avec succès ». Mesuré par sonde :
  ils n'ont **aucune unité de montage** dans cette VM. Je n'invente pas la cause,
  je l'écris comme non tranchée — et je la signale, parce que si ça valait aussi
  sur un hôte réel, chaque reboot changerait les clés d'hôte SSH.
- **I5 — `modprobe zfs` ne prouve pas l'épinglage du noyau.** Mesuré : un nœud
  avec seulement `boot.supportedFilesystems = ["zfs"]` tourne en 6.18.53 **et**
  obtient un module ZFS. Le subtest est renommé pour ce qu'il prouve (« le
  support ZFS est fonctionnel »), et `stc.relics.zfs.kernel` est consigné comme
  non couvert — épingler `uname -r` rougirait à chaque bump de nixpkgs.
- **I6 — j'avais choisi le timer non discriminant.** `services.zfs.trim.enable`
  vaut **déjà `true`** en amont (mesuré sur un nœud nu), donc `zpool-trim.timer`
  existe sans aucune relique. `zfs-scrub.timer` est absent sans la relique,
  présent ici, **et porte une valeur d'option** (`OnCalendar=monthly` =
  `scrubInterval`). Assert échangé : il discrimine et couvre une option.
- **I7 — la sortie de `systemctl cat stc-grow-pool.service` était jetée.** Le
  script rendu est là où atterrissent trois options du cogitator et la règle
  `partSep` de la relique. Asserts ajoutés sur `growpart /dev/nvme0n1 3` et
  `zpool online -e vmpool /dev/nvme0n1p3` — ce dernier prouve que le « p » n'est
  inséré que parce que le nom de périphérique finit par un chiffre.
- **I3 — ma note de portée se contredisait** (« exactement une unité en échec …
  les **deux** sont vérifiées »), texte resté de la version épinglée. Réécrite.
- **I8 — la conséquence du `mkDefault` n'était pas là où un consommateur la
  lit.** Elle vivait dans le commentaire de la relique, le message de commit et
  ce ledger : trois endroits qu'un consommateur ne lit jamais. Les deux pages de
  `relics/aws.md` ont maintenant une section qui dit l'autre tranchant : **tout
  module composé dans l'hôte peut désormais éteindre la console série en
  silence**, et sur EC2 c'est souvent le seul retour dans une machine dont le SSH
  ne répond plus — avec le `mkForce true` à poser si l'hôte en dépend.

Minor pris au passage, parce que c'était du texte faux que j'avais écrit : M3
(l'endpoint NTP est la revendication de la relique **AWS**, pas networking ; et la
note Quad9 exigée par la décision 5 avait disparu — rétablie comme non
observable), M5 (« forcé » est faux : `usePredictableInterfaceNames` perd un
simple arbitrage de priorité), M6 (« priorité 10 — sous `mkForce` à 50 » se lisait
comme *plus faible que*, alors que 10 gagne), M1 (`--wait` rétabli : la cible
`multi-user.target` active ne garantit pas que systemd a fini), M4 (`journalctl -b
-u zfs-rollback.service` au lieu d'un grep de la description, qui rougissait si on
reformulait la relique et embarquait le `poolName` par défaut).

Reportés : M2 (le proving **exige** maintenant la dégradation — rendre
`stc-grow-pool` tolérant à l'absence de pool le rendrait rouge), M7 (la branche
`else` de `partSep`, cas `xvda`, n'est exercée par rien).

**M8 — observation produit, pas un défaut de cette branche, et elle mérite son
propre arbitrage.** Je présentais « le rollback échoue et le boot continue » comme
la nouvelle rassurante. Pour une relique dont le contrat est « chaque boot est un
départ propre », un rollback qui échoue sans arrêter le boot veut dire qu'un hôte
monte avec **une racine sale et que personne n'est prévenu** (`Wants` +
`Before=sysroot.mount`, aucun `Requires`). Enregistrer ça au positif est la façon
la plus sûre de ne jamais le remarquer.
