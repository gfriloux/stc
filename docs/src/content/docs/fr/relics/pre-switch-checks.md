---
title: Contrôles pré-switch
description: Refuser d'activer le closure d'un autre host, et afficher le diff lors d'un déploiement distant.
---

**Module :** `stc.nixosModules.relics-pre-switch-checks`

`system.preSwitchChecks` lance des contrôles shell sur la **machine cible**, après
la copie du closure mais **avant** son activation. Un contrôle qui sort non-zéro
avorte le switch, l'ancien système restant debout.

Cette relique y place deux contrôles. Les deux visent des modes de défaillance
contre lesquels un consommateur ne peut pas se protéger seul.

## 1. Déployer le closure du mauvais host

Un consommateur multi-hosts déploie avec des commandes quasi identiques :

```bash
nixos-rebuild switch --flake .#clochette   --target-host vous@clochette.example
nixos-rebuild switch --flake .#RogueLeader --target-host vous@rogueleader.home
```

Inversez l'attribut de flake ou la cible, et le closure du host A s'active sur le
host B. Rien ne l'arrête. Sur un serveur Docker le résultat est immédiat et
moche : mauvais conteneurs, mauvais routeurs Traefik, mauvais utilisateurs,
mauvais secrets — et si le changement touche SSH ou sudo, possiblement aucun
retour en arrière.

## 2. Aucun diff lors d'un déploiement distant

En local, `nh os switch` montre ce qui change. `nixos-rebuild --target-host` ne
montre rien : l'opérateur active un closure sur un host de production sans voir
quels paquets ont bougé.

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.relics.preSwitchChecks.enable` | bool | `false` | Active les contrôles |
| `stc.relics.preSwitchChecks.hostnameGuard` | bool | `true` | Avorte sauf si le closure appartient au host courant |
| `stc.relics.preSwitchChecks.closureDiff` | bool | `true` | Affiche un diff `dix` avant d'activer |

`cogitator-docker-server` active cette relique, les deux contrôles compris. Tout
autre profil, `dreadnought` inclus, est à une ligne :

```nix
stc.relics.preSwitchChecks.enable = true;
```

:::caution[Ça peut avorter un déploiement qui marchait]
Le garde-fou compare le nom d'hôte réellement porté par la machine à celui pour
lequel le closure entrant a été construit. Si les deux diffèrent aujourd'hui sur
vos hosts — un nom écrasé par DHCP ou `cloud-init`, une config dont le
`networking.hostName` n'a jamais été corrigé — votre prochain `nixos-rebuild`
avorte.

Votre build ne casse pas. Seule l'activation s'arrête, et l'ancien système
continue de tourner. Trois sorties, par ordre de préférence :

1. corriger l'écart — il vous dit quelque chose de vrai ;
2. `stc.relics.preSwitchChecks.hostnameGuard = false;` si vous ne voulez pas du
   garde-fou ;
3. `NIXOS_NO_CHECK=1 nixos-rebuild switch …` pour un déploiement ponctuel.
:::

## Quand le garde-fou se déclenche

| Situation | Garde-fou | Pourquoi |
|-----------|-----------|----------|
| action `switch`, `test`, `check` | actif | Les trois touchent le système courant |
| action `boot` | **actif** | Volontairement contraire aux *switch inhibitors* d'amont, qui l'ignorent : écrire l'entrée de bootloader du mauvais host est précisément la catastrophe, et elle n'apparaît qu'au redémarrage suivant |
| action `dry-activate` | ignoré | Rien n'est activé, donc avorter n'empêcherait aucun dégât |
| `/run/booted-system` absent | ignoré | Une installation est en cours — voir plus bas |
| `networking.hostName` vide | ignoré | Un host nommé par DHCP n'a pas de nom attendu à comparer |

Le nom attendu est gravé à l'évaluation depuis `networking.hostName`. Ce n'est pas
circulaire : le contrôle voyage *dans* le closure entrant, donc cette valeur est
par construction le nom du host pour lequel ce closure a été construit.

La comparaison porte sur le **nom court**, la partie avant le premier point des
deux côtés, parce que systemd peut avoir posé le FQDN quand `networking.domain`
est défini, et qu'une comparaison stricte avorterait un déploiement correct. Le
compromis est explicite : deux hosts de même nom court mais de domaines
différents ne sont pas distingués.

### Pourquoi le cas de l'installation compte

`nixos-install` — et donc `nixos-anywhere`, qui est la façon d'installer les
[schematics](/stc/fr/schematics/) de STC — active le nouveau système dans un
chroot `nixos-enter`. Ce chroot ne bind-monte que `/dev`, `/sys` et `/proc` : donc
`/run` appartient à la cible fraîchement installée et il est vide, tandis que
`/proc/sys/kernel/hostname` est toujours celui de l'**installateur**. Sans le test
`/run/booted-system`, le garde-fou avorterait toute installation neuve. Il est
porteur, pas défensif.

## La seule échappatoire est `NIXOS_NO_CHECK=1`

C'est un fait mesuré, pas une préférence. srvos propose une variable
`EXPECTED_HOSTNAME` pour ça ; elle n'atteint pas le contrôle quand on déploie avec
`nixos-rebuild` :

- `nixos-rebuild-ng` lance `switch-to-configuration` sous `/usr/bin/env -i` avec
  une **liste blanche fermée** de trois variables — `LOCALE_ARCHIVE`,
  `NIXOS_NO_CHECK`, `NIXOS_INSTALL_BOOTLOADER` ;
- il enveloppe le tout dans `systemd-run -E` pour les trois mêmes ;
- et seule `NIXOS_NO_CHECK` figure dans le `env_keep` de sudo.

Une variable à nous n'atteindrait rien : il n'y en a donc aucune.

:::note[Ce que coûte l'échappatoire]
`NIXOS_NO_CHECK=1` désactive **tous** les contrôles pré-switch, y compris les
*switch inhibitors* d'amont. C'est le prix d'une échappatoire qui marche
démontrablement, face à une qui ne marche pas en silence.
:::

## Il n'y a pas de prompt

srvos demande confirmation sur stdin. Sous `nixos-rebuild --target-host`, le
script tourne à travers SSH sous `systemd-run --pipe`, où stdin n'est pas un
terminal fiable — et sous le `set -euo pipefail` qu'impose
`pkgs.writeShellApplication`, un `read` sur un stdin vide retourne non-zéro et
avorte le switch de toute façon.

Prompter est donc une manière non déterministe d'écrire *avorter*. Le garde-fou
avorte, et son message nomme les deux issues.

## Le diff de closure

Informatif, et incapable de faire échouer un switch : `dix` est appelé avec un
`||` final, donc un outil de diff qui plante affiche un avertissement et le
fragment sort quand même à 0. C'est vérifié par le comportement dans
`provings/docker-server.nix`, en passant au script un chemin de closure
inexistant et en vérifiant qu'il réussit toujours.

Il ajoute `dix` (~4 Mio déballés, présent dans le cache binaire) au closure de
tout host qui l'active. D'où une bascule séparée : coupez-le et gardez le
garde-fou.

Pour utiliser `nvd` à la place — les deux n'ont pas la même ligne de commande,
donc une option de paquet serait ici un piège :

```nix
stc.relics.preSwitchChecks.closureDiff = false;

system.preSwitchChecks.myDiff = ''
  ${pkgs.nvd}/bin/nvd diff /run/current-system "$1"
'';
```

## Écrire votre propre contrôle

Les noms de fragments ne sont pas cosmétiques : en amont ils sont rendus par
`lib.mapAttrsToList`, donc ils s'exécutent dans l'**ordre des noms
d'attributs**. Le garde-fou de cette relique s'appelle `stcAbortWrongHost` pour
trier avant `stcClosureDiff` — sinon un déploiement sur le mauvais host affiche
d'abord le diff de deux closures sans rapport, et pousse le message d'abandon
hors de l'écran. Gardez-le en tête pour nommer les vôtres.

Chaque fragment reçoit le closure entrant en `$1` et le verbe d'action en `$2`,
tourne dans un `( set -e … ) >&2` (donc stdout est déjà stderr : aucune
redirection à écrire), et est concaténé avec les autres dans un unique
`pkgs.writeShellApplication`. Ce dernier point a des dents : **shellcheck tourne
au build**, donc une expansion non quotée ou une variable inutilisée casse la
construction du système, et pas seulement un déploiement.

## Voir aussi

- [Vue d'ensemble des reliques](/stc/fr/relics/) — toutes les reliques
- [Profil Docker Server](/stc/fr/cogitator/docker-server/) — active cette relique
- [Variante VM](/stc/fr/relics/vm-variant/) — l'autre moitié du garde-fou : démarrer le host avant de le déployer
