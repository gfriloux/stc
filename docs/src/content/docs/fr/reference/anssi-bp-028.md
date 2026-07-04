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
| `pid_max`, `perf_cpu_time_max_percent`, `perf_event_max_sample_rate`, `panic_on_oops` | R9 | ⚪ | Réglages R9 non repris par STC |
| `kernel.modules_disabled=1` | R10 | ⚪ | Non implémenté — casse le chargement à la demande ; à évaluer au cas par cas |

## `relics.hardening.network`

| Réglage STC | Règle | Statut | Note |
|-------------|-------|--------|------|
| `net.ipv4.conf.*.rp_filter` | R12 | ✅ | Via `strictReversePathFilter` |
| `net.ipv4.conf.*.accept_redirects=0` (+ IPv6) | R12 | ✅ | |
| `net.ipv4.conf.*.secure_redirects=0` | R12 | ✅ | |
| `net.ipv4.conf.*.send_redirects=0` | R12 | ✅ | |
| `net.ipv4.icmp_ignore_bogus_error_responses=1` | R12 | ✅ | |
| `net.ipv4.tcp_syncookies=1` | R12 | ✅ | |
| `net.ipv4.icmp_echo_ignore_broadcasts=1` | R12 | 🟡 | Bonne pratique, hors liste R12 stricte |
| `ip_forward`, `accept_source_route`, `arp_*`, `route_localnet`, `tcp_rfc1337`, `bpf_jit_harden`, `accept_local`, `shared_media` | R12 | ⚪ | Réglages R12 non repris par STC |
| Désactivation IPv6 | R13 | ⚪ | STC garde IPv6 (bibliothèque générique) |

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
