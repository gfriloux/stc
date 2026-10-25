---
title: SMART
description: Les alertes de défaillance disque de smartd, livrées par ta propre commande.
---

**Module :** `stc.nixosModules.relics-smart`

Un pool ZFS passe en `DEGRADED` une fois que le disque a déjà lâché. SMART le
voit venir : secteurs réalloués ou en attente, erreurs non corrigeables,
température. La relique fait tourner smartd sur chaque disque compatible SMART
et confie chaque alerte à une commande que tu fournis.

Aucun cogitator ne l'active. Un profil ne peut pas savoir si son hôte a de
vrais disques : tu l'actives là où elle s'applique.

```nix
stc.relics.smart = {
  enable = true;
  notifyCommand = ''
    ${pkgs.curl}/bin/curl -s --max-time 10 \
      -H "Title: [$STC_SMART_HOSTNAME] $STC_SMART_FAILTYPE on $STC_SMART_DEVICE" \
      -d "$STC_SMART_MESSAGE" \
      "https://ntfy.sh/$(cat ${config.sops.secrets."ntfy/topic".path})"
  '';
};
```

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.relics.smart.enable` | bool | `false` | Active la relique |
| `stc.relics.smart.autodetect` | bool | `true` | Surveille chaque disque compatible SMART présent au démarrage ; `false` ne surveille que `services.smartd.devices` |
| `stc.relics.smart.defaults` | string | voir plus bas | Directives smartd.conf appliquées à chaque disque |
| `stc.relics.smart.hostname` | string | `networking.hostName` | Exposé dans `STC_SMART_HOSTNAME` |
| `stc.relics.smart.notifyCommand` | lines | `""` | Extrait shell lancé à chaque alerte. **Obligatoire** : vide, le build échoue |
| `stc.relics.smart.notifyTimeoutSec` | entier positif | `60` | Secondes accordées à `notifyCommand` avant qu'il soit tué |

La valeur par défaut de `defaults` :

```
-a -o on -S on -s (S/../.././02|L/../../6/03) -W 4,45,55
```

| Directive | Sens |
|---|---|
| `-a` | Tous les contrôles de santé, attributs et journaux d'erreurs |
| `-o on -S on` | La collecte hors ligne et la sauvegarde d'attributs du disque lui-même |
| `-s (S/../.././02\|L/../../6/03)` | Test court chaque jour à 02:00, test long le samedi à 03:00 |
| `-W 4,45,55` | Signale un saut de 4 °C, journalise à 45 °C, alerte à 55 °C |

Pour changer quoi que ce soit, remplace la chaîne entière. La relique ajoute
elle-même les directives de notification.

## La commande et son environnement

La relique n'envoie ni mail, ni ntfy, ni webhook : elle lance `notifyCommand`,
comme la [relique de notification Docker](/stc/fr/relics/docker/). La commande
lit ses propres secrets.

| Variable | Contenu |
|---|---|
| `STC_SMART_DEVICE` | Le disque tel que smartd le nomme : `/dev/sda [SAT]` |
| `STC_SMART_MESSAGE` | Le message de smartd : `Device: /dev/sda [SAT], Temperature 56 Celsius reached critical limit of 55 Celsius` |
| `STC_SMART_FAILTYPE` | `Health`, `Usage`, `SelfTest`, `ErrorCount`, `CurrentPendingSector`, `Temperature`, …, ou `EmailTest` |
| `STC_SMART_HOSTNAME` | L'option `hostname` |

smartd attend la fin de la commande avant de contrôler quoi que ce soit
d'autre. La relique la tue donc au bout de `notifyTimeoutSec` : un webhook
bloqué ne doit pas arrêter tous les contrôles SMART. Sa sortie (la réponse JSON
de ntfy, une erreur de curl) va dans le journal sous l'étiquette
`stc-smart-notify` (`journalctl -t stc-smart-notify`).

Un problème qui persiste (secteurs en attente, disque qui chauffe) est renvoyé
**une fois par jour** jusqu'à sa correction : c'est le `-M daily` de smartd,
son défaut quand il garde un état, ce que la relique active (voir
[État](#état)). Ajoute `-M once` ou `-M diminishing` à `defaults` pour moins de
rappels.

Pour tester ta commande sur un vrai hôte, ajoute `-M test` à la fin de
`defaults` : smartd envoie alors une alerte `EmailTest` par disque à chaque
démarrage. L'option nixpkgs `services.smartd.notifications.test` n'a aucun
effet ici : nixpkgs n'ajoute `-M test` qu'avec ses propres canaux.

Ne mets pas de `-M exec` à toi dans `defaults`, `services.smartd.defaults` ou
une entrée de `services.smartd.devices`. smartd ne garde que le dernier, donc
`notifyCommand` ne tournerait jamais, et le build échoue pour le dire.

Les canaux de nixpkgs (`services.smartd.notifications.mail`, `wall`, `x11`)
sont coupés. Chacun ajouterait un second chemin d'alerte dans smartd.conf, et
`wall` est actif par défaut, alors que personne ne lit un wall sur un serveur
sans écran. En rallumer un fait échouer le build avec un message qui
l'explique. Pour recevoir un mail, envoie-le depuis `notifyCommand`.

## Où elle s'applique

:::caution[Pas de SMART sur un disque virtuel]
Un disque virtio, un volume EBS ou le disque d'une VM cloud n'a pas de SMART.
smartd ne trouve alors rien à surveiller, s'arrête, et `smartd.service`
apparaît en **échec**. C'est voulu : un moniteur qui tourne sans rien surveiller
se lirait comme une couverture. N'active pas la relique sur un hôte cloud
(`sarcophagus-aws`) ni sur une VM sans passthrough des disques.
:::

Elle a sa place sur les hôtes à disques physiques : `dreadnought`, un hôte
`sarcophagus-kvm` sur du matériel nu, un poste de travail. Elle compte le plus
sur un hôte à disque unique : pas de miroir pour se dégrader, et les snapshots
ZFS sont sur le disque qui meurt.

## État

smartd garde un état par disque sous `/var/lib/smartmontools` : historique des
attributs, extrêmes de température, dernier avertissement envoyé, prochain
test dû. Sans lui, chaque redémarrage renvoie les avertissements en cours ;
avec lui, les rappels sont quotidiens (plus haut). Le perdre ne coûte rien de
plus : le [manifeste d'état](/stc/fr/reference/state-manifest/)
le classe en `cache`.

## Épreuve

`provings/smart.nix` démarre une VM avec un disque SATA émulé qui répond au
SMART (QEMU annonce 31 °C) et abaisse la température critique à 30 °C :

- les alertes `EmailTest` et `Temperature` de smartd lui-même arrivent dans
  `notifyCommand`, avec le disque (`/dev/sda [SAT]`), le nom d'hôte et le
  message dans l'environnement, et la sortie de la commande arrive dans le
  journal ;
- smartd.conf n'a qu'un chemin d'alerte, celui de la relique ;
- le fichier d'état existe sous `/var/lib/smartmontools` ;
- un second nœud avec un seul disque virtio montre `smartd.service` en échec
  avec le code de sortie « aucun disque » de smartd, et aucune alerte.
