---
title: Épreuves
description: nixosTests internes qui bootent une VM et vérifient qu'un cogitator se comporte comme promis.
sidebar:
  order: 0
---

Une **épreuve** (proving) est un test de comportement : un `nixosTest` qui boote
une VM avec un cogitator activé et vérifie qu'il fait réellement ce qu'il
prétend — sysctls effectifs, services configurés comme voulu, etc. Là où
`nix flake check` et les Purity Seals prouvent qu'un flake *évalue*, les épreuves
prouvent qu'un système *fonctionne*. C'est le Rite of Proving du machine spirit.

Les épreuves sont une **QA interne de STC**. Ce n'est pas une API destinée aux
consommateurs — ils ne les importent jamais.

## Hors du gate, volontairement

Les épreuves sont exposées sous `legacyPackages.<system>.provings.*`, un arbre
d'outputs que `nix flake check` **ignore délibérément**. Elles ne font donc
**pas partie du gate `just ci`** : un test de VM est lourd, et le gate CI reste
rapide et statique.

- On les lance à la main : `just test` (chaque épreuve builde et exécute sa VM).
- Linux uniquement (`x86_64-linux` / `aarch64-linux`) — l'attribut est vide ailleurs.
- Builder : `pkgs.testers.runNixOSTest`.

**Ce que `just test` coûte maintenant.** Quatorze épreuves, **vingt boots de VM** —
`vm`, `gaming`, `home-desktop`, `docker-server` et `smart` démarrent deux nœuds chacune, `dreadnought` en
déclare un second qu'elle ne démarre jamais, `docker-server` un troisième, et `sarcophagus-kvm` démarre son
nœud unique deux fois — et les clôtures contiennent
KDE deux fois (`workstation` et `plasma`), Steam une fois, les 31 paquets nommés
de la trousse enginseer, et GIMP, VLC et Zen Browser pour le profil desktop. Sur un
store froid, ça fait quelques Gio de téléchargement ; à chaud, la plupart des
scripts finissent en 23 à 30 s, `enginseer` en 25 s.
Les deux sarcophages sortent du lot, parce que chacun **construit une image
disque dans sa propre VM avant même que son test démarre** : `sarcophagus-kvm`
tourne ensuite 66 s pour ses deux boots, et `sarcophagus-aws` 32 s pour le
sien. C'est dit explicitement parce que
la discipline qui compte, c'est de lancer `just test` avant de fermer une branche
qui a touché un cogitator : une recette trop lourde à lancer est un gate qui cesse
discrètement d'en être un. Pour itérer, builder une seule épreuve —
`nix build .#legacyPackages.x86_64-linux.provings.<nom> -L` — et lancer la recette
complète avant la clôture.

À ne pas confondre avec `forge/purity-seals/`, qui produit des *builders de checks*
réutilisables par les flakes **consommateurs**. Les épreuves testent STC ; elles
ne s'exportent pas.

## Lancer une épreuve

```bash
just test
# ou, directement :
nix build .#legacyPackages.x86_64-linux.provings.hardening -L --no-write-lock-file
```

## Couverture

| Épreuve | Cogitator testé | Ce qu'elle vérifie |
|---------|-----------------|--------------------|
| `hardening` | `cogitator-hardening` | Durcissement sysctl kernel et réseau effectif ; SSH par clés uniquement, login root refusé |
| `docker-server` | `cogitator-docker-server` | Les unités des conteneurs portent leur image épinglée et les flags de healthcheck ; les réseaux docker, le hook notify `OnFailure` et les timers de health-watch sont câblés ; la config statique Traefik est rendue avec le plugin bouncer CrowdSec et l'endpoint socket-proxy ; les garde-fous docker avertissent exactement du port public et du montage de socket brut sans label — ni du conteneur labellisé, ni des 80/443 du Traefik de STC et du proxy, ni d'une écoute sur loopback, mais d'un port ajouté à Traefik ; de rien sur un nœud qui les décline ; et, lu sur un troisième nœud jamais démarré, du repli de Traefik sur le socket brut et d'un imposteur portant le nom du proxy quand la relique proxy est coupée |
| `workstation` | `cogitator-workstation` | Le profil câble ses trois concerns : le socle de durcissement (sysctl kernel/réseau, blacklist de modules) est effectif, le `pcscd` YubiKey est présent, et l'unité display-manager du bureau existe |
| `vm` | `cogitator-vm` | L'utilisateur primaire est dans `wheel`, son shell fish de login fonctionne et le lingering est actif ; une clé déclarée via `authorizedKeys` authentifie réellement en SSH, et pas seulement le port 22 qui répond ; le timer de GC part chaque semaine et son script porte bien la rétention déclarée ; Docker est absent par défaut et, sur un second nœud, le chemin opt-in câble à la fois le daemon et le groupe `docker` |
| `plasma` | `cogitator-plasma` | SDDM est bien le display manager et tourne en Wayland avec la session Plasma par défaut ; le fichier de session existe dans le répertoire que sddm désigne réellement ; les deux réglages de la relique (`keyboardLayout`, `sddmTheme`) atteignent la configuration rendue ; le portail XDG porte le joker que la relique configure ; rtkit, le pont ALSA 32 bits et le `default.target` qui démarre WirePlumber avec la session graphique sont en place ; gvfs et tumbler sont joignables depuis la session |
| `gaming` | `cogitator-gaming` | Steam est câblé, avec les règles udev qui rendent une manette utilisable sans root ; le pilote VDPAU/VAAPI de la relique AMD atteint l'arbre de pilotes fusionné ; les trois revendications de la relique Pipewire (rtkit, pont ALSA 32 bits, compat PulseAudio) sont en place ; Steam Remote Play est fermé par défaut et, sur un second nœud, ouvre à la fois sa plage UDP et ses ports TCP |
| `sarcophagus-kvm` | `cogitator-sarcophagus-kvm` | Démarre l'image qcow2 que le profil existe pour produire, deux fois sur le même disque : les datasets ZFS que le profil déclare sont bien ce qui est monté (`vmpool/root`, `vmpool/nix`, `vmpool/persist`), la relique crée elle-même la référence `@blank` que le builder d'image ne livre pas, le rollback de l'initrd tourne et *réussit*, et après un reboot un témoin posé sur le dataset racine a disparu tandis que ceux de `/persist` et du chemin déclaré via `impermanence.extraDirectories` ont survécu — l'empreinte de la clé d'hôte SSH restant inchangée, et le compte rendu d'échec de la relique restant totalement muet sur ce chemin sain |
| `sarcophagus-aws` | `cogitator-sarcophagus-aws` | Démarre l'image raw de l'AMI que le profil existe pour produire, sur un disque **plus grand que l'image** : le pool ZFS grandit réellement pour remplir le volume qui est dessous (`stc-grow-pool` va au bout *et* `zpool list` dépasse la taille de l'image), les datasets du profil sont bien ce qui est monté, `/boot` est un ESP FAT dont le label résout vers le périphérique monté, les deux paramètres noyau AWS qui discriminent sont actifs, `xen_fbfront` est blacklisté, les règles udev EC2 sont posées, et les pilotes réseau des **deux** classes d'instance sont demandés — celui de Xen échouant à s'insérer sur ce banc *sans faire échouer le boot*, ce qui est précisément ce qui permet à une seule image de servir Nitro et Xen |
| `enginseer` | `cogitator-enginseer` (Home Manager) | Active le profil pour un utilisateur de test dans une VM et vérifie ses revendications de runtime : les trois alias qu'il déclare se résolvent dans un shell réellement lancé (pas les six que rend aussi `programs.lsd`), `oh-my-posh` s'initialise depuis le thème que le cogitator livre, `git` choisit lui-même `delta` comme pager de diff avec l'`interactive.diffFilter` de delta en place, direnv est accroché à fish avec nix-direnv et silencieux, `FZF_CTRL_R_COMMAND` est posée et vide donc Ctrl-R appartient à atuin, `~/.ssh/config` porte le multiplexage **sans** le bloc par défaut legacy de Home Manager, le `pinentry-program` de gpg-agent est le `pinentry-curses` sans tête, et la saveur catppuccin déclarée atteint le thème de bat |
| `home-desktop` | `cogitator-desktop` (Home Manager) | Deux nœuds. Sur le profil **seul** : kitty est absent, la relique ghostty rend son unité utilisateur et ses overrides, zen-browser atteint le profil utilisateur sous le nom `zen-beta`, les `gimp` et `vlc` propres au cogitator sont installés, et l'option `fonts` de la relique ghostty rend les polices Nerd visibles de `fc-list`. Sur un nœud portant les **deux** profils Home Manager : le `mkForce pinentry-qt` de desktop gagne l'arbitrage contre le `mkDefault pinentry-curses` d'enginseer — la seule interaction entre cogitators vérifiée de toute la suite — et une revendication de chaque profil tient encore sous composition |
| `dreadnought` | `cogitator-dreadnought` | Cinq reliques composées sur un même hôte démarrent, avec exactement une unité chargée en échec faute de pool ; le support ZFS est fonctionnel sur le noyau booté ; les deux paramètres noyau AWS qui discriminent atteignent `/proc/cmdline` ; le script d'agrandissement porte les `poolName`, `ebsDisk` et `ebsPartition` du profil ; le timer de scrub ZFS porte `scrubInterval` ; la persistance explicite est bien bind-montée, y compris une entrée posée par l'option du cogitator ; le durcissement survit à la composition ; le rollback d'impermanence a tourné dans l'initrd et échoué comme prévu, et cet échec est lisible depuis le système démarré via `stc-impermanence-state.service` et non plus seulement dans un journal d'initrd |
| `smart` | `relics-smart` (aucun cogitator ne l'active) | Sur un disque SATA émulé qui répond au SMART, les alertes `EmailTest` et `Temperature` de smartd lui-même arrivent dans `notifyCommand` avec l'environnement documenté, et sa sortie arrive dans le journal ; smartd.conf ne porte qu'un chemin d'alerte ; le fichier d'état existe. Un second nœud avec un seul disque virtio montre `smartd.service` en échec avec le code « aucun disque » de smartd, et aucune alerte |
| `polkit-units` | `relics-polkit-units` (aucun cogitator ne l'active) | Des utilisateurs sans privilèges lancent `systemctl` : un membre du groupe redémarre, arrête et démarre l'unité nommée et redémarre une unité couverte seulement par le préfixe, et pilote une instance de modèle listée ; une autre instance, une autre unité, un autre verbe, geler/dégeler, `enable`, un non-membre, un appel du gestionnaire sans unité et `systemd-run --unit=` sous un nom préfixé ou délégué sont tous refusés, sans erreur de règle dans le journal de polkit. Joué deux fois, la seconde avec `/proc` remonté en `hidepid=2` comme le pose la relique de durcissement |
| `heartbeat` | `relics-heartbeat` (aucun cogitator ne l'active) | Face à un petit serveur HTTP local : un job réussi pinge, de même qu'un job sorti avec un statut déclaré dans `SuccessExitStatus=` ; un lancement manuel du heartbeat ne pinge pas ; un job en échec, un oneshot arrêté en cours et un service arrêté en cours (que systemd enregistre en `Result=success`) ne pingent pas ; un récepteur injoignable ne fait échouer que l'unité heartbeat ; l'URL n'apparaît dans aucun fichier d'unité ni script |

## Ajouter une épreuve

1. Créer `provings/<nom>.nix` — une fonction `{self}: { name; nodes; testScript; }`.
   Le nœud importe le vrai module du flake via `self.nixosModules.cogitator-<nom>`.
   Un cogitator Home Manager prend `{self, inputs}` à la place, parce que son nœud
   doit importer le module NixOS de Home Manager depuis un input — voir *Vérifier
   un cogitator Home Manager* plus bas. Les deux signatures coexistent à dessein.
2. La câbler dans `provings/default.nix` sous `legacyPackages.provings.<nom>`.
3. **L'ajouter à la recette `test` du `Justfile`.** Une épreuve enregistrée dans
   `provings/default.nix` mais absente de la recette ne tourne jamais, et un
   `just test` vert est alors un faux vert — cette étape n'est pas optionnelle.
4. Ajouter une ligne au tableau de couverture ci-dessus (et son miroir anglais).

## Paquets unfree dans une épreuve

`cogitator-gaming` active `programs.steam`, et Steam est unfree. Le `pkgs` que
flake-parts donne au registre n'autorise pas l'unfree, donc cette épreuve ne peut
pas être bâtie depuis lui — et aucune des deux façons de relâcher ça depuis
l'intérieur du test ne marche. Les deux sont mesurées fermées :

| Tentative | Résultat |
|---|---|
| `nixpkgs.config.allowUnfree = true` dans le nœud | `error: nixpkgs.config is set to read-only` |
| `node.pkgs = <instance>` | `error: node.pkgs is defined multiple times` — `runNixOSTest` la définit lui-même |

L'instance doit donc être celle qui **bâtit** le test :

```nix
pkgs-unfree = import inputs.nixpkgs {
  inherit system;
  config.allowUnfree = true;
};
# …
gaming = pkgs-unfree.testers.runNixOSTest (import ./gaming.nix {inherit self;});
```

Elle est cantonnée à cette seule ligne du registre, comme `forge/default.nix` en
cantonne une pour la licence BSL de Terraform. Les autres épreuves gardent un
`drvPath` identique au bit près avec l'instance en place — c'est comme ça que ça a
été vérifié plutôt que supposé, même si le contrôle tient de la formalité :
`pkgs-unfree` est une liaison paresseuse que Nix ne force jamais pour elles.

**Ce que ce cantonnement achète, et ce qu'il n'achète pas.** Aucune autre sortie du
flake ne peut tirer un paquet unfree par ce biais. Mais à l'intérieur de cette
épreuve, la clôture **entière** du nœud est évaluée avec `allowUnfree = true` — donc
si une relique composée dans `cogitator-gaming` se met plus tard à tirer un firmware
unfree ou un pilote propriétaire, cette épreuve l'accepte en silence là où toutes les
autres échoueraient à l'évaluation. L'instance cantonne par sortie, pas par paquet.

## Vérifier un cogitator Home Manager

`cogitator-enginseer` est un profil Home Manager et non NixOS, et
[#50](https://github.com/gfriloux/stc/issues/50) laissait délibérément le
mécanisme ouvert — *« doesn't need to be `runNixOSTest` if that's the wrong tool
for a HM-only module »*. C'est le bon outil, et la raison vaut d'être écrite parce
que l'option la moins chère est tentante.

**Pourquoi pas construire `home.activationPackage` ?** Parce que ça prouve que la
configuration *évalue et construit*, ce que `nix flake check` et les Purity Seals
prouvent déjà. Une épreuve qui se réduirait à un `nix build` n'ajouterait rien au
gate tout en portant le nom d'une épreuve. Or les revendications d'enginseer sont
des revendications de runtime : un alias qui se résout dans un shell réellement
lancé, `delta` qui est le pager que `git` choisit lui-même, la variable de session
qui confie Ctrl-R à atuin. Rien de tout ça n'est visible dans un `drvPath`.

Le nœud importe donc `inputs.home-manager.nixosModules.home-manager` et attache le
cogitator à un utilisateur de test par `home-manager.users.<u>.imports`.
L'activation devient alors une unité systemd ordinaire du nœud — mesuré,
`home-manager-<u>.service` — et `wait_for_unit` s'applique comme partout
ailleurs. C'est aussi pourquoi les deux épreuves Home Manager prennent `inputs` là où les
neuf autres ne prennent que `self` : `self.homeModules.*` seul ne peut pas
attacher une configuration home à un nœud.

**Quatre concessions de banc**, dans le même esprit que les cinq du patron image
externe. Aucune n'est une recommandation de câblage pour un consommateur :

| Option | Pourquoi |
|---|---|
| `users.users.<u>.shell = pkgs.fish` | Home Manager ne pose pas le shell de connexion — mesuré. Sans ça, aucun fish ne démarre, donc la moitié « shell de connexion » du profil ne serait pas observable. Sur le nœud `enginseer` et sur le nœud composé de `home-desktop` seulement : le nœud desktop seul ne pose aucun shell, puisque ce profil n'en revendique pas |
| `programs.fish.enable = true` | Imposé par une assertion amont dès qu'un utilisateur a fish en shell de connexion : sinon fish « [manque] les répertoires nix de base dans son PATH et peut rendre impossible la connexion de cet utilisateur ». Satisfaite plutôt que muselée par `ignoreShellProgramCheck`, parce que ces nœuds se connectent vraiment. Appariée à la ligne du dessus, donc absente elle aussi du nœud desktop seul |
| `home-manager.useGlobalPkgs = true` | HM utilise le `pkgs` du nœud au lieu d'importer sa propre nixpkgs. Une seule instance à l'évaluation — et la note sur le scoping unfree ci-dessus reste vraie pour les épreuves Home Manager, ce qu'une seconde instance rendrait faux en silence |
| `home-manager.useUserPackages = true` | Les paquets atterrissent dans `users.users.<u>.packages`, donc sous `/etc/profiles/per-user/<u>`, un chemin déterministe — ce qui rend vérifiable l'assert zen-browser de `home-desktop`, cette relique ne rendant aucun fichier. Mesuré, et plus étroit qu'il n'y paraît : `useUserPackages` déplace le `drvPath` d'activation, tandis que `useGlobalPkgs` seul est identique au byte au défaut — donc seule la première change la clôture, et la seconde gagne sa place en retirant une seconde instance nixpkgs |

Mesuré et à dire : **aucun des deux cogitators Home Manager n'a besoin de
l'instance unfree.** `gaming` reste la seule épreuve unfree de la suite.

### Ce que mesurer d'abord a disqualifié

Le nœud de référence ici est celui qui porte Home Manager et l'utilisateur de
test mais **aucun cogitator STC**. Dessus, HM rend exactement cinq fichiers
(`environment.d/10-home-manager.conf`, trois `fontconfig/conf.d/*`,
`systemd/user/tray.target`) plus deux `.keep`, et `programs.fish.enable` comme
`services.gpg-agent.enable` valent `false`. Cinq candidats d'assertion ont été
corrigés ou écartés contre lui, et chacun n'aurait rien prouvé :

- **Six des neuf alias fish ne sont pas à STC.** `ls`, `ll`, `la`, `lt`, `lla`
  et `llt` viennent du module `programs.lsd` de Home Manager — et pire,
  `environment.shellAliases` de NixOS vaut **lui-même** `{l, ll, ls}` par défaut,
  donc vérifier `ll` aurait été vert sans aucun cogitator. Seuls `cat → bat`,
  `cp → xcp` et `ping → prettyping` sortent de ce profil.
- **`delta` n'est pas câblé sur `core.pager`.** L'intégration passe par
  `[pager] diff/log/show/blame` et `interactive.diffFilter` — `[delta]` ne porte
  que `features`. `core.pager` n'est pas posée, donc une vérification dessus
  n'aurait pas été un faux vert mais un rouge franc : `git config --get` sort
  en 1.
- **`programs.direnv.silent` n'écrit le mot « silent » nulle part.** Il rend une
  section `[global]` avec `log_filter = "^$"`.
- **`programs.fzf.historyWidget.command = ""` ne change pas `config.fish`.**
  Mesuré contre le contre-factuel, la seule différence entre les deux fichiers
  rendus est un chemin de store : le réglage passe par `hm-session-vars.fish`
  sous la forme `FZF_CTRL_R_COMMAND`. Mesuré dans les deux sens : le cogitator la
  rend **posée et vide**, et le défaut de l'option (`null`) ne rend aucune
  variable du tout — c'est ce qui fait de « posée et vide » un état distinguable
  et non une tautologie.
- **Le choix du pinentry n'est pas dans l'unité systemd.** Il atterrit dans
  `~/.gnupg/gpg-agent.conf` sous forme d'une ligne `pinentry-program` ; l'unité
  rendue n'en dit rien.

Une assertion avait besoin d'un **contre-factuel** pour être vérifiable du tout.
`programs.ssh.enableDefaultConfig = false` est une revendication sur ce qui est
*absent* : le remettre à `true` ajoute `AddKeysToAgent`, `Compression`,
`ForwardAgent`, `HashKnownHosts`, `ServerAliveCountMax`, `ServerAliveInterval` et
`UserKnownHostsFile`. C'est donc l'absence de ceux-là qui distingue les deux cas,
là où la présence de `ControlMaster` ne distingue rien.

### Deux nœuds, et la revendication qui réclamait un contre-factuel impossible

`home-desktop` porte deux nœuds. Le profil **seul** est l'épreuve de #50 à
proprement parler, et l'isolement est délibéré : une épreuve nommée
`home-desktop` qui rougirait parce que quelque chose a cassé dans enginseer
serait un mauvais diagnostic. Le nœud **composé** existe pour une seule
revendication, écrite dans `cogitator/home/desktop.nix` :

```nix
# Graphical pinentry for gpg-agent. Overrides the headless-safe default set
# by cogitator-enginseer; inert if gpg-agent is not enabled.
services.gpg-agent.pinentry.package = lib.mkForce pkgs.pinentry-qt;
```

La première moitié est un arbitrage de priorité entre deux cogitators, et aucun
nœud seul ne peut le montrer : `enginseer` vérifie le côté `pinentry-curses`,
`composed` vérifie le côté `pinentry-qt`.

**La seconde moitié — « inert if gpg-agent is not enabled » — n'est
délibérément pas vérifiée en VM.** Le plan prévoyait de vérifier qu'aucune unité
utilisateur `gpg-agent` n'existe sur le nœud desktop seul. Mesuré contre le nœud
de référence : il n'en a pas non plus, puisque `services.gpg-agent.enable` vaut
`false` sans aucun cogitator. L'assertion serait verte quoi que fasse STC.
L'inertie est une propriété d'**évaluation** — desktop seul pose
`pinentry.package` à `pinentry-qt` alors que `gpg-agent.enable` reste `false`,
donc rien ne la consomme — et la lire depuis la VM demanderait d'interpoler
l'option depuis l'évaluation même qui a construit le nœud. Même traitement que le
cas négatif de `docker-server` et que `boot.zfs.devNodes` dans `sarcophagus-aws`.

Deux autres candidats que la mesure a corrigés avant écriture :

- **Le binaire de zen-browser s'appelle `zen-beta`, pas `zen`** — le cogitator
  importe `inputs.zen-browser.homeModules.beta`. Vérifier le nom évident aurait
  été rouge. C'est aussi la seule de ces reliques à ne rendre **aucun**
  fichier, donc le profil utilisateur est le seul endroit où elle est observable,
  ce qui est précisément ce que `useUserPackages` apporte à cette épreuve.
- **Les polices Nerd ne sont pas joignables au chemin évident.** Elles sont ce
  qu'installe `stc.relics.gui.ghostty.fonts.enable` (défaut `true`) — la seule
  option propre à STC de ces reliques au-delà de leurs `enable`. Elle était
  portée par la relique kitty jusqu'au retrait de celle-ci (#1). Mais
  `environment.pathsToLink` ne porte aucune entrée
  `/share/fonts`, donc `/etc/profiles/per-user/<u>/share/fonts` n'est jamais
  peuplé : les polices sont dans la dérivation `home-manager-path`, que
  `~/.config/fontconfig/conf.d/10-hm-fonts.conf` désigne. L'assertion passe donc
  par `fc-list` — la question de comportement, *la session trouve-t-elle ces
  polices*, est à la fois la bonne et la seule à avoir une réponse vraie.

### Limite de périmètre — la configuration, pas un agent vivant

L'épreuve ne vérifie pas que `gpg-agent` *tourne*. C'est une unité utilisateur, il
faudrait une session utilisateur vivante ; ce que le cogitator décide, c'est quel
pinentry l'agent porte, et ça se lit dans la configuration rendue. L'agent qui
tourne est celui de l'amont.

Non vérifié non plus : la simple présence de paquets dans le `PATH`. Une liste de
paquets prouve qu'une liste de paquets a été écrite.

### Limite de périmètre — les reliques GUI sont prouvées configurées, pas lancées

`home-desktop` ne démarre aucune session graphique, la même limite que l'épreuve
`plasma` énonce pour ses propres raisons. ghostty et Zen Browser sont donc
prouvés **installés et configurés** — leurs fichiers rendus, leurs binaires dans
le profil, leurs polices visibles de fontconfig — et non prouvés *démarrables*.
Lancer un terminal orienté GPU et un navigateur dans une VM mesurerait
l'empaquetage de l'amont plutôt que le câblage de STC, qui est tout ce que ces
reliques apportent.

## Démarrer une vraie image — le patron « image externe »

Douze des quatorze épreuves laissent le pilote de test synthétiser un nœud.
`sarcophagus-kvm` ne le peut pas : la revendication de son profil **est** le
disque, et sur un nœud synthétisé le module qemu-vm remplace `fileSystems` par le
sien à la priorité 10 — ni le pool, ni les datasets, ni le rollback ne seraient
observables.

Elle suit donc le `nixos/tests/qemu-vm-external-disk-image.nix` de nixpkgs : le
nœud déclare l'image, et le pilote démarre *cette image* au lieu d'une racine à
lui. Le script de test pose une surcouche copy-on-write au-dessus du chemin du
store et y pointe `NIX_DISK_IMAGE` — c'est aussi ce qui permet au même disque de
conserver ses écritures d'un boot à l'autre.

Cinq options de nœud le rendent possible. Aucune n'est un correctif produit —
l'amont les expose exactement pour ça — et chacune a été mesurée, pas devinée :

| Option | Pourquoi |
|---|---|
| `virtualisation.directBoot.enable = false` | démarrer le GRUB de l'image plutôt que le noyau du pilote |
| `virtualisation.mountHostNixStore = false` | le store vit dans l'image |
| `virtualisation.fileSystems = lib.mkForce {}` | l'échappatoire documentée à l'écrasement de `fileSystems`. Avec elle, `findmnt /` répond `vmpool/root` et la couche disque devient assertable |
| `virtualisation.bootLoaderDevice = "/dev/vda"` | `qemu-vm.nix` épingle `boot.loader.grub.device` à `/dev/disk/by-id/virtio-root` à la priorité 10, ce qui bat le `mkForce` du cogitator ; le builder d'image échoue alors à installer GRUB |
| `system.switch.enable = true` | `nixos-test-base.nix` le désactive par défaut, et `nixos-install` dans le builder d'image a besoin de `switch-to-configuration` |

Les deux dernières ne se rencontrent qu'en lançant : elles sortent toutes deux
comme une erreur de **build d'image**, pas d'évaluation, et celle de GRUB signale
un périphérique inexistant plutôt qu'un conflit de priorités.

`provings/sarcophagus-aws.nix` reprend ce patron, et exactement deux choses
diffèrent. L'image est raw et non qcow2 — mesuré dans
`make-single-disk-zfs-image.nix`, `format = "raw"` donne le suffixe `.img`, donc
la surcouche se prend sur `nixos.root.img` avec `-F raw`. Et la surcouche reçoit
une **taille** : 8 Gio sur une image de 5 Gio, donc la partition 3 s'arrête
avant la fin du périphérique et `stc-grow-pool` a quelque chose à agrandir.
Trois tailles entrent en jeu et en confondre deux fausse l'arithmétique —
mesuré sur l'artefact, la partition ZFS fait 4096 Mio (`rootSize`), le *fichier*
image fait 5120 Mio (l'amont le dimensionne à `bootSize + rootSize`, et
`bootSize` vaut 1024 par défaut), et le disque virtuel fait 8 Gio. Le seuil de
l'épreuve est donc adossé au **pool**, qui passe des 3,999 Gio de p3 à
6,75 Gio. C'est
une instance EC2 sur un volume EBS plus grand que son AMI, et c'est la seule
revendication que ni `dreadnought` (qui ne lit que la *chaîne* de ce script) ni
`sarcophagus-kvm` (dont le disque fait exactement la taille de son image) ne
peuvent atteindre. Mesuré au banc : le pool arrive à 6,75 Gio.

Les cinq lignes de concession et le bloc `qemu-img` sont **recopiés** dans la
seconde épreuve plutôt que factorisés. Deux occurrences ne font pas une
abstraction, et une fonction partagée cacherait précisément les lignes qu'un
lecteur doit avoir sous les yeux pour faire confiance au banc. Si un troisième
sarcophage arrive, on factorisera alors, avec trois cas en vue.

## Limite de périmètre — dreadnought ne voit pas la couche disque

`cogitator-dreadnought` est le profil qui possède les disques, et une VM de
`nixosTest` remplace l'essentiel de ce que ça veut dire. Le module qemu-vm
surcharge des jeux d'options entiers à la priorité 10, qui **gagne** contre tout
ce qu'une relique peut écrire (`mkForce` est à 50, une définition nue à 100). Sur
ce nœud, mesuré :

| Ce que le profil déclare | Ce que la VM de test a |
|---|---|
| montages ZFS pour `/`, `/nix`, `/persist` | le jeu `fileSystems` propre à la VM |
| `boot.loader.grub.device` = le disque EBS | `/dev/disk/by-id/virtio-root` |
| l'endpoint NTP de la relique AWS | `timesyncd` est coupé dans le socle de test |
| les résolveurs Quad9 de la relique networking | aucun `/etc/resolv.conf` sur le nœud |
| `usePredictableInterfaceNames` | `false` — la relique le pose en `mkDefault`, il perd donc un simple arbitrage de priorité, il n'est pas forcé |
| `serial-getty@ttyS0` activé | réclamé par l'instrumentation du test |

Donc import du pool, montage des datasets, périphérique de boot, endpoint NTP,
résolveurs et console série ne sont **pas vérifiés** — pour des raisons de
framework, pas de code. Le vrai banc d'essai de la couche disque est l'image
qcow2 de `local-vm` bootée à la main (`just build`, `just run`, `just ssh`), celle
qui a prouvé le changement d'import ZFS en v0.13.0.

**La console série AWS n'a aucune couverture**, et ça vaut d'être dit deux fois :
le getty est coupé ici, et `console=ttyS0,115200n8` n'est pas un substitut
utilisable non plus — mesuré, le socle de test pose
`virtualisation.qemu.consoles = ["ttyS0,115200n8" "tty0"]` sur un nœud **nu**,
donc cette chaîne est sur la ligne de commande du noyau quoi que fasse la relique.
Seuls `nvme_core.io_timeout` et `random.trust_cpu` discriminent, et seuls ces deux
sont vérifiés.

**Ce que `sarcophagus-aws` a changé à ce tableau, et ce qu'elle n'a pas changé.**
Démarrer l'image réelle lève les limites de framework ci-dessus : l'import du
pool, les montages de datasets, le périphérique de boot et — c'est l'objet de
cette épreuve — la croissance du pool au runtime y sont tous vérifiés. Trois
trous ne sont **pas** levés, et ont été re-mesurés plutôt que supposés :

- **La console série** reste non couverte. Le getty est en `lib.mkDefault` depuis
  #45, donc il perd un contest de priorité ordinaire face à l'instrumentation au
  lieu d'entrer en collision avec elle — c'est ce qui a rendu possible toute
  épreuve de ce profil, mais ça veut quand même dire qu'aucun getty ne tourne.
  Le cas de la chaîne de débit est plus subtil : sous le patron image externe,
  `directBoot` est coupé et la ligne de commande du noyau vient du GRUB de
  l'image, donc `virtualisation.qemu.consoles` ne l'atteint plus et la chaîne
  *pourrait* discriminer là. L'établir demanderait de construire une seconde
  image sans la relique, ce que l'épreuve ne paie pas — donc ce n'est pas
  vérifié, plutôt que vérifié sur une prémisse non mesurée.
- **Le point NTP AWS** reste non couvert, pour une raison qui survit au patron
  image externe : `services.timesyncd.enable` est mesuré `false` sur un nœud nu,
  sur un nœud ZFS seul **et** sur le nœud STC, donc aucun
  `/etc/systemd/timesyncd.conf` n'est rendu et il n'y a nulle part où lire
  `169.254.169.123`. C'est `qemu-vm.nix:1489` qui l'éteint — un `false` nu à
  priorité normale, commenté *« Don't run ntpd in the guest »* — et non
  `nixos-test-base.nix`, qui ne mentionne jamais timesyncd.
- **`boot.zfs.devNodes`** (`/dev`, contre le défaut `/dev/disk/by-id`) discrimine
  à l'évaluation et ne peut pas du tout être vérifié sur ce banc : la seule
  lecture au runtime serait le chemin de store d'un script d'unité interpolé
  depuis la *même* évaluation, donc une tautologie — et un disque virtio **a**
  des entrées `by-id`, donc le défaut importerait le pool aussi bien. Le banc ne
  peut pas distinguer la relique du défaut.

**La persistance explicite, en revanche, est vérifiée** — c'est la seule
revendication côté disque qui survive. `environment.persistence` ne passe pas par
`fileSystems` : il produit des bind-mounts systemd, que qemu-vm laisse
tranquilles. Donc `/var/log`, `/var/lib/nixos`, `/etc/machine-id` et une entrée
posée via l'option `impermanence.extraDirectories` du cogitator sont tous
contrôlés au `findmnt`. Les quatre entrées `/etc/ssh/ssh_host_*` que la relique
déclare aussi n'ont **aucune unité de montage**, ici comme sur un hôte réel — et
`sarcophagus-kvm` a tranché pourquoi, avec une réponse qui n'est pas l'évidente.
L'amont rend les `files` par `mount-file.bash`, qui pose un lien symbolique au
lieu d'un bind mount quand la cible n'existe pas encore ; or ce script tourne
aussi comme script d'*activation* `persist-files`, que `nixos-install` exécute
dans le builder d'image, alors que `/persist` est encore vide. Les liens sont donc
cuits dans l'image, donc présents dans `@blank`, donc restaurés par chaque
rollback — et `mount-file.bash` trouve alors un lien qui pointe déjà sur sa cible
et ne fait rien. sshd lit la clé à travers, depuis `/persist`. Mesuré de part et
d'autre d'un rollback : l'empreinte de la clé d'hôte ne change pas.

**Ce que le boot établit quand même.** Le service de rollback d'impermanence
tourne dans l'initrd, échoue faute de pool, et le boot continue malgré tout —
l'unité est tirée par `Wants`, pas `Requires`. Le système booté est donc
`degraded`, et l'épreuve **épingle** l'ensemble des unités en échec à exactement
une, en filtrant sur la colonne `loaded` de systemd : `zfs-rollback` n'a pas de
fragment dans le système booté, donc le fait que son échec initrd soit encore
listé après le switch-root varie d'un lancement à l'autre, et le filtre retire
cette non-détermination sans élargir ce qui est accepté.

Non vérifié non plus : `services.udisks2.enable = false`, que la relique AWS pose
pour garder GTK hors d'un serveur headless (mesuré `false` sur un nœud nu aussi,
donc l'assert ne distinguerait pas la relique du défaut) ; et
`stc.relics.zfs.kernel`, puisque épingler `uname -r` rougirait à chaque bump de
nixpkgs — mesuré, un nœud avec seulement `boot.supportedFilesystems = ["zfs"]`
obtient un module ZFS fonctionnel sur un noyau plus récent, donc charger le module
prouve que le support ZFS marche, pas que l'épinglage est celui de la relique.

## Limite de périmètre — durcissement des montages

L'épreuve `hardening` ne vérifie **pas** les options de montage
(`/tmp` + `/dev/shm` en `noexec`, `/proc` en `hidepid=2`). Le relic les délivre
via `fileSystems`, mais le module qemu-vm de nixosTest remplace tout l'attrset
`fileSystems` par `mkVMOverride` (priorité 10), qui écrase le `mkForce`
(priorité 50) du relic. Ces montages n'existent jamais dans la VM de test : une
vérification à l'exécution échouerait pour des raisons de framework, pas réelles.
Le durcissement à base de sysctl n'est pas affecté et est bien vérifié.

## Limite de périmètre — plasma vérifie la configuration, pas une session graphique

L'épreuve `plasma` attend `multi-user.target` puis lit sur disque la
configuration rendue et les fichiers d'unités. Elle ne lance pas de session
Plasma : c'est lourd dans une VM, et la session elle-même est celle de l'amont,
pas celle de STC.

**Ce qu'elle ne vérifie volontairement pas, et pourquoi.** Chaque assert candidat
a été mesuré trois fois — sur un nœud `nixosTest` nu, sur un nœud portant le
module `plasma6` de nixpkgs sans STC, et sur le nœud STC — pour que chacun sache
distinguer la relique d'un défaut. Quatre candidats ont échoué à ce test et ont
été écartés :

- `services.pulseaudio.enable` et `services.xserver.enable` valent déjà `false`
  sans aucune de ces reliques, donc « PulseAudio est coupé » et « pas de serveur
  X » seraient vrais quoi que fasse STC.
- `services.pipewire.enable` et `xdg.portal.enable` sont posés par le module
  `plasma6` de nixpkgs lui-même : les **unités utilisateur** Pipewire et portail
  existent donc même en retirant la relique Pipewire de STC du cogitator.
  L'épreuve vérifie à la place ce qui discrimine vraiment : `rtkit`, la ligne
  `libs.32Bit` dans `/etc/alsa/conf.d/49-pipewire-modules.conf`, et le
  `default.target` posé sur WirePlumber.

Un assert incapable de distinguer la relique du défaut ne prouve rien et se lit
comme une couverture, ce qui est pire qu'un manque assumé.

## Limite de périmètre — docker-server vérifie le câblage, pas les conteneurs

L'épreuve `docker-server` vérifie le **câblage** généré par les reliques, pas des
conteneurs démarrés. Une VM nixosTest est isolée du réseau, donc `docker pull` ne
peut pas aboutir et les services de conteneurs ne montent jamais. C'est
volontaire : STC possède le câblage réutilisable, pas le cycle de vie des images.
L'épreuve fournit des images factices (jamais tirées) et inspecte les fichiers
d'unités générés avec `systemctl cat`, qui les lit depuis le disque quel que soit
l'état d'exécution ; le démarrage des conteneurs n'est pas attendu.
