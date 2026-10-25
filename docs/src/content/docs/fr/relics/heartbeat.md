---
title: Heartbeat
description: Un job planifié pinge ta supervision à chaque succès, pour qu'un job qui ne tourne plus déclenche une alerte.
---

**Module :** `stc.nixosModules.relics-heartbeat`

Une sauvegarde qui ne tourne plus ne déclenche aucune alerte. Chaque contrôle
voit un hôte sain, parce que rien n'est cassé : quelque chose n'a simplement
pas eu lieu. Un « dead man's switch » comble ce trou. Le job pinge une URL
**à chaque succès**, et le récepteur (moniteur push
d'[Uptime Kuma](https://uptime.kuma.pet/),
[healthchecks.io](https://healthchecks.io), …) alerte quand les pings
cessent d'arriver.

```nix
stc.relics.heartbeat = {
  enable = true;
  units."borgbackup-job-remote".urlFile = config.sops.secrets."kuma/push-borg".path;
};
```

Aucun cogitator ne l'active. Le récepteur, l'URL et la fenêtre d'alerte sont
à toi ; STC fournit le câblage.

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.relics.heartbeat.enable` | bool | `false` | Active la relique |
| `stc.relics.heartbeat.units.<nom>.urlFile` | chemin absolu | — | Fichier contenant l'URL à pinger, lu à l'exécution. `<nom>` est le service tel que dans `systemd.services` (sans `.service`) |
| `stc.relics.heartbeat.units.<nom>.packageUnit` | bool | `false` | L'unité vient de `systemd.packages` (`fstrim`, …) : saute la vérification d'existence, qui ne la voit pas |
| `stc.relics.heartbeat.retries` | entier | `3` | Nouvelles tentatives de curl pour un ping raté |
| `stc.relics.heartbeat.timeoutSec` | entier | `10` | Secondes accordées à chaque tentative |

Le build échoue si un service listé :

- n'est pas un vrai service (ni `script`, ni `ExecStart`), sauf si
  `packageUnit` indique qu'il vient d'un paquet. Une unité renommée ne peut
  donc pas perdre son heartbeat en silence ;
- est désactivé (`enable = false`) ;
- pose `RemainAfterExit` : il reste actif après son succès et ne déclenche
  jamais le ping.

## Seulement sur succès

Un ping sur « le job a tourné » cacherait exactement la panne que la relique
doit attraper. Elle ne pinge que si le job a **réussi** :

| Le service surveillé… | Ping |
|---|---|
| réussit : sort en 0, ou avec un statut qu'il déclare dans `SuccessExitStatus=` | oui |
| échoue | non |
| est un oneshot arrêté en cours (`systemctl stop`, extinction) | non : il finit en échec |
| est un service qui tourne en continu, arrêté en cours | non, bien que systemd l'enregistre comme un succès |

La dernière ligne explique pourquoi la relique fait plus que poser le
`OnSuccess=` de systemd. systemd compte le SIGTERM d'un service à l'arrêt
comme une fin propre. Le service finit alors avec `Result=success`, et
`OnSuccess=` se déclenche. Avant de pinger, l'unité heartbeat vérifie donc
comment le job s'est vraiment terminé : `Result=success`, et un processus
principal **sorti** de lui-même, sans avoir été tué.

Elle le lit dans l'instantané que systemd transmet à une unité `OnSuccess=`
(`MONITOR_SERVICE_RESULT`, `MONITOR_EXIT_CODE`, `MONITOR_UNIT`), pas dans
l'état courant de l'unité, qu'une relance rapide (`Restart=`) aurait déjà
remis à zéro. Lancée à la main, `stc-heartbeat-<nom>.service` n'a pas
d'instantané, et ne pinge pas.

Ce que la vérification ne voit pas : un programme qui intercepte SIGTERM et
sort de lui-même en 0, comme beaucoup de démons qui s'arrêtent proprement.
Pour systemd, cette exécution s'est terminée : elle pinge. Les deux lignes
« arrêté en cours » ne valent que pour un processus que le signal tue
réellement.

## Comment ça tourne

Pour chaque service surveillé `<nom>`, la relique ajoute
`OnSuccess=stc-heartbeat-<nom>.service` et cette unité heartbeat. Le ping
tourne dans sa propre unité, pas à l'intérieur du job surveillé :

- **Un ping raté ne fait jamais échouer le job.** Si le récepteur est
  injoignable, `stc-heartbeat-<nom>.service` échoue seule, et le job garde
  son succès.
- **Le bac à sable du job ne compte pas.** Un job sans accès réseau
  (`PrivateNetwork=`) a quand même son heartbeat.
- **Le ping tourne sous un utilisateur temporaire.** Il utilise
  `DynamicUser`, pas root.

## L'URL est un secret

Qui connaît l'URL peut alimenter le récepteur et faire taire l'alerte. Elle
reste donc hors du store Nix :

- Elle est lue à l'exécution depuis `urlFile`, via `LoadCredential`.
- Elle arrive à curl par l'entrée standard (`--config -`), jamais sur la ligne
  de commande, où tout utilisateur local pourrait la lire dans la liste des
  processus.

## Hors périmètre

- **Les jobs dans un conteneur.** Ils n'ont pas d'unité systemd par
  exécution. Pour eux, le contrôle honnête porte sur le résultat : l'âge du
  dernier fichier de dump.
- **Les services `Type=forking` sans processus principal connu.** systemd
  n'enregistre pas leur sortie, donc ils ne pingent jamais.
- **Une exécution qui se termine pendant l'extinction.** systemd peut alors
  refuser de mettre le heartbeat en file, et le ping est perdu. Le récepteur
  voit une fenêtre manquée.

## Épreuve

`provings/heartbeat.nix` démarre une VM avec un petit serveur HTTP local qui
joue le récepteur :

- un job qui réussit pinge, de même qu'un job qui sort avec un statut déclaré
  dans `SuccessExitStatus=` ;
- lancer l'unité heartbeat à la main ne pinge pas ;
- un job qui échoue ne pinge pas ;
- un oneshot arrêté en cours finit en échec et ne pinge pas ;
- un service qui tourne en continu, arrêté en cours, finit en
  `Result=success`, son heartbeat tourne, et la vérification l'empêche de
  pinger ;
- serveur arrêté, l'unité heartbeat échoue, et le job garde
  `Result=success` ;
- l'URL est absente du fichier d'unité et du script du heartbeat.
