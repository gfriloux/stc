---
title: Survie des serveurs
description: Un hôte sans écran redémarre seul au lieu d'attendre une console où personne n'est assis.
---

**Module :** `stc.nixosModules.relics-server-survivability`

Les défauts de NixOS supposent qu'il y a quelqu'un devant la machine. Sur un
hôte distant, chacun des défauts ci-dessous transforme une panne réparable en
machine morte :

| Défaut amont | Ce qui arrive sur un hôte sans écran | Ce que fait la relique |
|---|---|---|
| Mode d'urgence actif | Un montage ou un fsck raté fait tomber le boot dans un shell root que personne ne peut atteindre, et sshd ne démarre jamais | Saute le mode d'urgence : le boot continue, et on peut se connecter pour enquêter |
| Pas de watchdog | Un noyau ou un PID 1 figé attend la console du fournisseur, l'IPMI ou un reboot à la main | Arme le watchdog matériel (30 s) |
| `kernel.panic = 0` | Un noyau en panique reste figé indéfiniment | `panic=30` sur la ligne de commande du noyau |
| GRUB garde 100 générations, systemd-boot toutes | Les générations remplissent une petite ESP jusqu'à faire échouer l'installation du chargeur : l'hôte démarre encore, mais ne peut plus être mis à jour | Garde 5 générations au boot |
| Mise en veille permise | Un `systemctl suspend` égaré met l'hôte hors ligne, et rien ne peut le réveiller | Refuse la veille et l'hibernation |

Activée par défaut (`lib.mkDefault`) par les quatre profils serveur :
[docker-server](/stc/fr/cogitator/docker-server/),
[dreadnought](/stc/fr/cogitator/dreadnought/),
[sarcophagus-aws](/stc/fr/cogitator/sarcophagus-aws/) et
[sarcophagus-kvm](/stc/fr/cogitator/sarcophagus-kvm/).

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.relics.serverSurvivability.enable` | bool | `false` | Active la relique |
| `stc.relics.serverSurvivability.disableEmergencyMode` | bool | `true` | Pas de shell d'urgence en stage 2 (`systemd.enableEmergencyMode = mkDefault false`) |
| `stc.relics.serverSurvivability.panicReboot` | bool | `true` | `panic=30` et `boot.panic_on_fail` sur la ligne de commande du noyau |
| `stc.relics.serverSurvivability.watchdog.enable` | bool | `true` | Arme le watchdog matériel |
| `stc.relics.serverSurvivability.watchdog.runtimeSec` | string | `"30s"` | `RuntimeWatchdogSec` |
| `stc.relics.serverSurvivability.bootGenerations` | null ou entier positif | `5` | `configurationLimit` de GRUB et de systemd-boot (en défaut) ; `null` garde celui du chargeur |
| `stc.relics.serverSurvivability.forbidSleep` | bool | `true` | `AllowSuspend=no`, `AllowHibernation=no` |

Chaque comportement a son propre interrupteur. Par exemple, pour garder le shell
d'urgence sur un hôte joignable en IPMI :

```nix
stc.relics.serverSurvivability.disableEmergencyMode = false;
```

## Le watchdog a besoin d'un périphérique

`RuntimeWatchdogSec` ne protège que s'il existe un périphérique watchdog. Le
matériel nu en a généralement un. Une VM n'en a que si l'hyperviseur en expose
un : la machine q35 de QEMU fournit `iTCO_wdt`, ce qui n'est pas forcément le
cas des autres hyperviseurs. **Sans périphérique, systemd le journalise et
continue.** C'est sans danger, mais ça ne protège rien. Pour vérifier sur l'hôte :

```bash
journalctl -b -o cat _PID=1 | grep -i watchdog
# Watchdog running with a hardware timeout of 30s.   ← armé
```

Si un watchdog de firmware lent redémarre la machine à tort, augmente
`watchdog.runtimeSec`. `RebootWatchdogSec` n'est pas posé, parce que systemd lui
donne déjà 10 min par défaut.

## La panique et la relique de durcissement

La [relique de durcissement du noyau](/stc/fr/relics/hardening/) pose le sysctl
`kernel.panic` à `30`. Cette relique met la même valeur sur la ligne de
commande, ce qui couvre la fenêtre qui précède `systemd-sysctl`, initrd compris.
Comme les deux valeurs sont identiques, le délai ne change pas en cours de boot.
La relique n'écrit jamais le sysctl elle-même.

Un module d'image cloud de nixpkgs (`amazon-image.nix`, les configs Azure, GCE
et DigitalOcean) ajoute son propre `panic=1`. Combiné à cette relique, les deux
valeurs se retrouvent sur la ligne de commande et le noyau garde la dernière,
qui dépend de l'ordre de fusion des modules. Vérifie `/proc/cmdline` sur un tel
hôte.

## Reboot sur panique et arrêt d'urgence de l'impermanence

`disableEmergencyMode` ne touche que le stage 2. L'initrd garde sa propre cible
d'urgence, mais `panicReboot` pose aussi `boot.panic_on_fail`, ce qui fait
planter le noyau par l'initrd dès que cette cible démarre. Du coup,
[`stc.relics.impermanence.onRollbackFailure = "emergency"`](/stc/fr/relics/impermanence/)
ne s'arrêterait plus pour attendre un humain. Avec `panic=30`, il redémarrerait
toutes les 30 s tant que le rollback échoue.

La relique **refuse de construire** cette combinaison, et le message demande de
choisir :

```nix
# Garder l'arrêt, renoncer au reboot automatique sur échec d'initrd :
stc.relics.serverSurvivability.panicReboot = false;
# …ou garder le reboot, et laisser un rollback raté démarrer, marqué dégradé :
stc.relics.impermanence.onRollbackFailure = "continue";
```

## Pourquoi pas `profiles/headless.nix` de nixpkgs

Le profil amont couvre le mode d'urgence et la panique, mais il fait aussi deux
choses qui n'ont rien à faire ici :

- Il **désactive `serial-getty@ttyS0`**. Sur un VPS, la console série du
  fournisseur est souvent le seul accès hors bande.
- Il ajoute `nomodeset vga=0x317`, qui sont des choix d'affichage.

La relique choisit donc ses réglages un par un au lieu d'importer le profil.

## Épreuve

`provings/docker-server.nix` démarre le profil et fait chaque vérification deux
fois : sur un nœud qui porte la relique, puis sur un nœud où elle est coupée.
Les vérifications sont l'absence d'`emergency.service`, `panic=30` dans
`/proc/cmdline`, la ligne « Watchdog running … 30s » journalisée par systemd
lui-même, et `AllowSuspend=no`. Chacune doit réussir sur le premier nœud et
échouer sur le second.

## Voir aussi

- [Défauts surchargeables](/stc/fr/reference/overridable-defaults/)
- [Impermanence](/stc/fr/relics/impermanence/) : `onRollbackFailure`
