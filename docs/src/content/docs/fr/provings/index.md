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

**Ce que `just test` coûte maintenant.** Huit épreuves, **onze boots de VM** —
`vm` et `gaming` portent deux nœuds chacune, et `sarcophagus-kvm` démarre son
nœud unique deux fois — et les clôtures contiennent KDE deux fois (`workstation`
et `plasma`) et Steam une fois. Sur un store froid, ça fait quelques Gio de
téléchargement ; à chaud, la plupart des scripts finissent en 23 à 30 s.
`sarcophagus-kvm` sort du lot aux deux bouts : elle construit une image disque
dans sa propre VM avant même que le test démarre, puis son script tourne 63 s
pour les deux boots. C'est dit explicitement parce que
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
| `docker-server` | `cogitator-docker-server` | Les unités des conteneurs portent leur image épinglée et les flags de healthcheck ; les réseaux docker, le hook notify `OnFailure` et les timers de health-watch sont câblés ; la config statique Traefik est rendue avec le plugin bouncer CrowdSec et l'endpoint socket-proxy |
| `workstation` | `cogitator-workstation` | Le profil câble ses trois concerns : le socle de durcissement (sysctl kernel/réseau, blacklist de modules) est effectif, le `pcscd` YubiKey est présent, et l'unité display-manager du bureau existe |
| `vm` | `cogitator-vm` | L'utilisateur primaire est dans `wheel`, son shell fish de login fonctionne et le lingering est actif ; une clé déclarée via `authorizedKeys` authentifie réellement en SSH, et pas seulement le port 22 qui répond ; le timer de GC part chaque semaine et son script porte bien la rétention déclarée ; Docker est absent par défaut et, sur un second nœud, le chemin opt-in câble à la fois le daemon et le groupe `docker` |
| `plasma` | `cogitator-plasma` | SDDM est bien le display manager et tourne en Wayland avec la session Plasma par défaut ; le fichier de session existe dans le répertoire que sddm désigne réellement ; les deux réglages de la relique (`keyboardLayout`, `sddmTheme`) atteignent la configuration rendue ; le portail XDG porte le joker que la relique configure ; rtkit, le pont ALSA 32 bits et le `default.target` qui démarre WirePlumber avec la session graphique sont en place ; gvfs et tumbler sont joignables depuis la session |
| `gaming` | `cogitator-gaming` | Steam est câblé, avec les règles udev qui rendent une manette utilisable sans root ; le pilote VDPAU/VAAPI de la relique AMD atteint l'arbre de pilotes fusionné ; les trois revendications de la relique Pipewire (rtkit, pont ALSA 32 bits, compat PulseAudio) sont en place ; Steam Remote Play est fermé par défaut et, sur un second nœud, ouvre à la fois sa plage UDP et ses ports TCP |
| `sarcophagus-kvm` | `cogitator-sarcophagus-kvm` | Démarre l'image qcow2 que le profil existe pour produire, deux fois sur le même disque : les datasets ZFS que le profil déclare sont bien ce qui est monté (`vmpool/root`, `vmpool/nix`, `vmpool/persist`), la relique crée elle-même la référence `@blank` que le builder d'image ne livre pas, le rollback de l'initrd tourne et *réussit*, et après un reboot un témoin posé sur le dataset racine a disparu tandis que ceux de `/persist` et du chemin déclaré via `impermanence.extraDirectories` ont survécu — l'empreinte de la clé d'hôte SSH restant inchangée |
| `dreadnought` | `cogitator-dreadnought` | Cinq reliques composées sur un même hôte démarrent, avec exactement une unité chargée en échec faute de pool ; le support ZFS est fonctionnel sur le noyau booté ; les deux paramètres noyau AWS qui discriminent atteignent `/proc/cmdline` ; le script d'agrandissement porte les `poolName`, `ebsDisk` et `ebsPartition` du profil ; le timer de scrub ZFS porte `scrubInterval` ; la persistance explicite est bien bind-montée, y compris une entrée posée par l'option du cogitator ; le durcissement survit à la composition ; le rollback d'impermanence a tourné dans l'initrd et échoué comme prévu |

## Ajouter une épreuve

1. Créer `provings/<nom>.nix` — une fonction `{self}: { name; nodes; testScript; }`.
   Le nœud importe le vrai module du flake via `self.nixosModules.cogitator-<nom>`.
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
cantonne une pour la licence BSL de Terraform. Les cinq autres épreuves gardent un
`drvPath` identique au bit près avec l'instance en place — c'est comme ça que ça a
été vérifié plutôt que supposé, même si le contrôle tient de la formalité :
`pkgs-unfree` est une liaison paresseuse que Nix ne force jamais pour elles.

**Ce que ce cantonnement achète, et ce qu'il n'achète pas.** Aucune autre sortie du
flake ne peut tirer un paquet unfree par ce biais. Mais à l'intérieur de cette
épreuve, la clôture **entière** du nœud est évaluée avec `allowUnfree = true` — donc
si une relique composée dans `cogitator-gaming` se met plus tard à tirer un firmware
unfree ou un pilote propriétaire, cette épreuve l'accepte en silence là où toutes les
autres échoueraient à l'évaluation. L'instance cantonne par sortie, pas par paquet.

## Démarrer une vraie image — le patron « image externe »

Sept des huit épreuves laissent le pilote de test synthétiser un nœud.
`sarcophagus-kvm` ne le peut pas : la revendication de son profil **est** le
disque, et sur un nœud synthétisé le module qemu-vm remplace `fileSystems` par le
sien à la priorité 10 — ni le pool, ni les datasets, ni le rollback ne seraient
observables.

Elle suit donc le `nixos/tests/qemu-vm-external-disk-image.nix` de nixpkgs : le
nœud déclare l'image, et le pilote démarre *cette image* au lieu d'une racine à
lui. Le script de test pose une surcouche copy-on-write au-dessus du chemin du
store et y pointe `NIX_DISK_IMAGE` — c'est aussi ce qui permet au même disque de
conserver ses écritures d'un boot à l'autre.

Quatre options de nœud le rendent possible. Aucune n'est un correctif produit —
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

C'est le patron que #47 (`sarcophagus-aws`) doit reprendre.

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

**La persistance explicite, en revanche, est vérifiée** — c'est la seule
revendication côté disque qui survive. `environment.persistence` ne passe pas par
`fileSystems` : il produit des bind-mounts systemd, que qemu-vm laisse
tranquilles. Donc `/var/log`, `/var/lib/nixos`, `/etc/machine-id` et une entrée
posée via l'option `impermanence.extraDirectories` du cogitator sont tous
contrôlés au `findmnt`. Les quatre entrées `/etc/ssh/ssh_host_*` que la relique
déclare aussi n'ont **aucune unité de montage** dans cette VM ; savoir si elles
sont bind-montées sur un hôte réel n'est pas tranché ici, et ça compte — si elles
ne le sont pas, chaque reboot change les clés d'hôte SSH.

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
