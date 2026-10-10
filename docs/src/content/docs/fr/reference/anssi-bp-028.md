---
title: Conformité ANSSI-BP-028
description: Correspondance entre le durcissement STC et le guide ANSSI-BP-028 v2.0 de configuration GNU/Linux.
sidebar:
  order: 0
---

Les reliques de durcissement de STC sont traçables face aux recommandations
françaises **ANSSI-BP-028 v2.0** (*Recommandations de configuration d'un système
GNU/Linux*, 03/10/2022). Chaque réglage porte une référence `# ANSSI-BP-028 Rxx`
en commentaire dans le code ; cette page en est la matrice lisible.

C'est une **carte de fidélité, pas une certification**. Elle documente ce que font
les reliques actuelles — elle ne prétend pas que STC est un système conforme. La
conformité complète exige aussi le partitionnement disque, la gestion des secrets
et la sécurité physique/boot, qui relèvent du flake et du matériel du consommateur.

**Légende des statuts :** ✅ couvert · 🟡 partiel · ⚪ hors périmètre / non implémenté.

## Pourquoi pas CIS ?

Le CIS publie ses Benchmarks par distribution — Ubuntu, RHEL, Debian, Amazon
Linux — et il n'existe aucun Benchmark CIS pour NixOS. STC ne revendique donc
**aucune conformité CIS**, et le recouvrement des contrôles ne doit pas le
laisser croire : les sysctl noyau et réseau, SSH, la blacklist de modules et les
options de montage couvrent une bonne part de ce que demande CIS Level 1/2, mais
cette correspondance est informative, jamais normative. ANSSI-BP-028 est le
référentiel ; CIS n'est qu'un point de comparaison.

Les écarts relevés en comparant STC à CIS Level 1/2 sont suivis sur GitHub sous
l'étiquette
[`compliance-cis`](https://github.com/gfriloux/stc/labels/compliance-cis).

## Hors périmètre assumé

Aucune relique ne configure de politique de qualité de mot de passe ni de
verrouillage de compte (`pam_pwquality`, `pam_faillock`, expiration). SSH
n'accepte que les clés publiques, il n'y a donc aucun mot de passe à deviner à
distance, et les schematics posent `users.mutableUsers = false`, ce qui ne laisse
rien à arbitrer à ces contrôles PAM. Le risque résiduel sur la connexion console
locale est documenté — avec le raisonnement et la porte de sortie — dans
[`SECURITY_POLICY.md`](https://github.com/gfriloux/stc/blob/main/SECURITY_POLICY.md),
section *Threat model and non-goals*.

## Règles ANSSI-BP-028 concernées

| Règle | Sujet |
|-------|-------|
| R9  | Configuration sysctl du noyau |
| R10 | Désactivation du chargement de modules noyau |
| R11 | Module Yama (`ptrace_scope`) |
| R12 | Configuration sysctl réseau IPv4 |
| R13 | Désactivation d'IPv6 si inutilisé |
| R14 | Configuration sysctl système de fichiers |
| R28 | Partitionnement type et options de montage |

## `relics.hardening.kernel`

| Réglage STC | Règle | Statut | Note |
|-------------|-------|--------|------|
| `kernel.randomize_va_space=2` | R9 | ✅ | ASLR complet |
| `kernel.kptr_restrict=2` | R9 | ✅ | |
| `kernel.dmesg_restrict=1` | R9 | ✅ | |
| `kernel.perf_event_paranoid=3` | R9 | ✅ | Plus strict qu'ANSSI (2) |
| `kernel.unprivileged_bpf_disabled=1` | R9 | ✅ | |
| `kernel.sysrq=0` | R9 | ✅ | |
| `kernel.yama.ptrace_scope=1` | R11 | ✅ | |
| `fs.suid_dumpable=0` (+ coredump off, limite PAM) | R14 | ✅ | |
| `fs.protected_hardlinks=1` | R14 | ✅ | |
| `fs.protected_symlinks=1` | R14 | ✅ | |
| `fs.protected_fifos=2` | R14 | ✅ | |
| `fs.protected_regular=2` | R14 | ✅ | |
| `kernel.kexec_load_disabled=1` | (kexec) | 🟡 | ANSSI désactive kexec en compile-time (`CONFIG_KEXEC` non défini) ; STC utilise le sysctl runtime |
| `kernel.panic_on_oops=1` | R9 | ✅ | Couplé à `kernel.panic=30` — voir plus bas |
| `kernel.pid_max` | R9 | ✅ | Satisfait sans que STC écrive quoi que ce soit : le `sysctl.d/50-pid-max.conf` de systemd donne `4194304`, très au-dessus des `65536` de R9. Vérifié comme plancher dans `provings/hardening.nix` |
| `kernel.perf_cpu_time_max_percent`, `kernel.perf_event_max_sample_rate` | R9 | ⚪ | Évalués, non retenus — voir plus bas |
| `kernel.modules_disabled=1` | R10 | ⚪ | Verrouillage total non implémenté — casse le chargement à la demande. Voir `relics.hardening.modules` pour la forme souple (blacklist ciblée) |

### À propos de `panic_on_oops` et du délai de redémarrage

Un oops — `Oops:` ou `BUG:` dans `dmesg` — est une véritable faute noyau. Par
défaut, le noyau tue la tâche fautive et poursuit dans un état dont il ne peut
plus répondre. Plusieurs techniques d'exploitation tolèrent, voire provoquent
délibérément, une série d'oops (brute-force de KASLR, pulvérisation de tas) : ce
qui fait de chaque oops survécu un essai gratuit pour l'attaquant.
`panic_on_oops=1` met fin à cette boucle d'essais.

R9 s'arrête là, mais `panic_on_oops=1` seul *fige* la machine, car `kernel.panic`
vaut `0` par défaut — attendre indéfiniment. Sur un nœud headless, cela veut dire
aucun retour sans accès console. STC pose donc aussi `kernel.panic=30` : la
machine échoue toujours en fermeture, puis redémarre. Le délai est un ajout de
STC, pas une exigence de R9. Pour conserver une machine figée en vue d'une
analyse post-mortem, surcharge-le :

```nix
boot.kernel.sysctl."kernel.panic" = lib.mkForce 0;
```

À ne pas confondre avec `kernel.panic_on_warn`, qui réagit aux `WARN_ON()` — les
traces `WARNING: ... at <fichier>:<ligne>`, une assertion de développeur et non
une faute. Un défaut bénin de pilote en émet, donc paniquer dessus échangerait de
la disponibilité réelle contre rien. ANSSI ne le demande pas ; STC ne le pose pas.

Pour jauger le risque sur un hôte donné avant d'activer la relique, lis les
drapeaux de contamination du noyau :

```console
$ cat /proc/sys/kernel/tainted
```

Le bit 7 (valeur `128`, `TAINT_DIE`) est posé dès qu'un oops ou un `die()` s'est
produit depuis le démarrage. S'il reste éteint sous ta charge de travail,
`panic_on_oops=1` ne coûte rien en pratique. Le bit 9 (`512`) ne consigne qu'un
`WARNING`, que ce réglage ignore.

### À propos des deux limites de débit perf

R9 demande `perf_cpu_time_max_percent=1` et `perf_event_max_sample_rate=1`. STC
ne pose ni l'un ni l'autre, pour deux raisons. `perf_event_paranoid=3` ci-dessus
interdit déjà perf aux utilisateurs non privilégiés, donc ces deux réglages ne
bornent plus que le profilage de root — et root est de confiance dans le modèle
de menace de STC, donc cela n'achète aucune confidentialité. Ensuite, le noyau
s'autorégule déjà : quand le handler NMI d'échantillonnage devient trop coûteux,
il baisse le débit de lui-même, et le dit dans `dmesg` :

```
perf: interrupt took too long (4993 > 4967), lowering kernel.perf_event_max_sample_rate to 40000
```

Un `1` écrit en dur remplacerait ce contrôle adaptatif par une valeur 40000 fois
plus basse et rendrait le profilage inutilisable sur une machine que STC pourrait
tout à fait avoir à déboguer.

## `relics.hardening.network`

| Réglage STC | Règle | Statut | Note |
|-------------|-------|--------|------|
| `net.ipv4.conf.*.rp_filter` | R12 | ✅ | Via `strictReversePathFilter` |
| `net.ipv4.conf.*.accept_redirects=0` (+ IPv6) | R12 | ✅ | |
| `net.ipv4.conf.*.secure_redirects=0` | R12 | ✅ | |
| `net.ipv4.conf.*.send_redirects=0` | R12 | ✅ | |
| `net.ipv4.icmp_ignore_bogus_error_responses=1` | R12 | ✅ | |
| `net.ipv4.tcp_syncookies=1` | R12 | ✅ | |
| `net.ipv4.conf.*.accept_source_route=0` (+ IPv6) | R12 | ✅ | |
| `net.ipv4.tcp_rfc1337=1` | R12 | ✅ | Protection anti-assassinat TIME_WAIT |
| `net.core.bpf_jit_harden=2` | R12 | ✅ | Durcissement du JIT eBPF |
| `net.ipv4.conf.*.log_martians=1` | R12 | ✅ | Signal forensique seulement — `rp_filter` jette déjà les paquets |
| `net.ipv4.conf.*.arp_ignore=1`, `arp_announce=2` | R12 | 🟡 | Opt-in via `strictArp` (désactivé par défaut ; casse multi-homed / Docker) |
| `net.ipv4.icmp_echo_ignore_broadcasts=1` | R12 | 🟡 | Bonne pratique, hors liste R12 stricte |
| `ip_forward`, `route_localnet`, `accept_local`, `shared_media` | R12 | ⚪ | Réglages R12 non repris par STC |
| `net.ipv6.conf.*.accept_ra=0` | R13 | 🟡 | Opt-in via `strictIpv6RouterAdvertisements` (désactivé par défaut ; isole les hôtes SLAAC). Pas de retrait d'IPv6, juste un pas dans la direction de R13 |
| Désactivation IPv6 | R13 | ⚪ | STC garde IPv6 (bibliothèque générique) |

## `relics.hardening.modules`

| Réglage STC | Règle | Statut | Note |
|-------------|-------|--------|------|
| Blacklist `firewire-core/ohci/sbp2` (DMA) | R10 | 🟡 | Forme souple de R10 — blacklist ciblée, pas le verrouillage total `modules_disabled` |
| Blacklist `dccp`, `sctp`, `rds`, `tipc` (protocoles rares) | R10 | 🟡 | Même logique |
| Blacklist `cramfs`, `freevxfs`, `jffs2`, `hfs`, `hfsplus` (systèmes de fichiers legacy) | R10 | 🟡 | Même logique. `udf` et `usb-storage` laissés à `extraBlacklist` — les deux ont encore des usages légitimes |

## `relics.hardening.filesystem`

| Réglage STC | Règle | Statut | Note |
|-------------|-------|--------|------|
| `/tmp` `nosuid,nodev,noexec` | R28 | ✅ | `noexec` omis si `gaming=true` |
| `/proc` `hidepid=2` | R28 | ✅ | |
| `/dev/shm` `nosuid,nodev,noexec` | R28 | 🟡 | Même logique ; hors table R28 |
| Partitions séparées `/boot /var /home /usr /opt /srv /var/log /var/tmp` | R28 | ⚪ | STC ne partitionne pas — c'est le layout disko du schematic, pas une relique |

## `relics.hardening.ssh`

Le durcissement SSH (`PermitRootLogin no`, `PasswordAuthentication no`,
KexAlgorithms/Ciphers/Macs modernes) est **hors périmètre ANSSI-BP-028**. La
configuration de sshd est couverte par un guide ANSSI distinct,
*Recommandations pour un usage sécurisé d'(Open)SSH*. Elle figure ici uniquement
pour expliciter la frontière.
