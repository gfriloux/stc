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
| `gaming` | `cogitator-gaming` | Steam et ses règles matérielles sont câblés ; le pilote VDPAU/VAAPI de la relique AMD atteint l'arbre de pilotes fusionné ; les graphismes 32 bits et le pont ALSA 32 bits sont en place pour Proton et Wine ; Steam Remote Play est fermé par défaut et, sur un second nœud, ouvre exactement UDP 27031-27035 |

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
cantonne une pour la licence BSL de Terraform. Rien d'autre dans le flake ne gagne
le droit de tirer un paquet unfree en silence, et les cinq autres épreuves gardent
un `drvPath` identique au bit près avec l'instance en place — c'est comme ça que ça
a été vérifié plutôt que supposé.

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
