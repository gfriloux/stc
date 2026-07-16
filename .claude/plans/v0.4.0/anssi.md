# PLAN_ANSSI.md — Maintenance Plan: ANSSI-BP-028 compliance mapping

> Roadmap plan 2/4. Issu de la comparaison STC vs Sécurix/Bureautix (DINUM).
> À valider avant tout code. Suit le template de `PROCEDURE_PLANS.md`.
> Branche : `feat/anssi-reference`.

## Objective

Rendre le durcissement STC **traçable** face au référentiel officiel
**ANSSI-BP-028 v2.0** : chaque réglage renvoie à sa règle Rxx, et une matrice de
conformité honnête (couvert / partiel / hors périmètre) vit dans la doc.

## Why

Face à Sécurix (aligné ANSSI), STC n'a aucune boussole externe. Sans référentiel,
impossible de dire si le hardening est *suffisant*. Ce plan donne la cible.

## Décisions actées (2026-07-04)

1. Mapping **manuel** (pas de génération auto depuis le code — plus tard peut-être).
2. Doc **structurée** : nouvelle section `reference/` dans les docs Starlight
   (EN+FR), qui accueillera aussi le mapping matériel du plan 4.
3. **Pas de changement DESIGN.md** : `reference/` est une section du site de doc,
   pas un pilier du dépôt ; côté code, on n'ajoute que des commentaires.

## Source

PDF officiel **ANSSI-BP-028-EN v2.0** (03/10/2022), extrait par `pdftotext`.
Règles pertinentes : R8 (boot mémoire), R9 (sysctl noyau), R10 (modules_disabled),
R11 (ptrace_scope), R12 (sysctl réseau IPv4), R13 (désactivation IPv6),
R14 (sysctl fichiers), R28 (partitionnement + options de montage).

## La matrice (source de vérité de l'exécution)

Statuts : ✅ couvert · 🟡 partiel · ⚪ hors périmètre / non implémenté.

### `relics/nixos/hardening/kernel.nix`

| Réglage STC | Règle ANSSI | Statut | Note |
|---|---|---|---|
| `kernel.randomize_va_space=2` | R9 | ✅ | |
| `kernel.kptr_restrict=2` | R9 | ✅ | |
| `kernel.dmesg_restrict=1` | R9 | ✅ | |
| `kernel.perf_event_paranoid=3` | R9 | ✅ | STC plus strict (ANSSI=2) |
| `kernel.unprivileged_bpf_disabled=1` | R9 | ✅ | |
| `kernel.sysrq=0` | R9 | ✅ | |
| `kernel.yama.ptrace_scope=1` | R11 | ✅ | |
| `fs.suid_dumpable=0` | R14 | ✅ | + `systemd.coredump.enable=false`, PAM core limit |
| `fs.protected_hardlinks=1` | R14 | ✅ | |
| `fs.protected_symlinks=1` | R14 | ✅ | |
| `fs.protected_fifos=2` | R14 | ✅ | |
| `fs.protected_regular=2` | R14 | ✅ | |
| `kernel.kexec_load_disabled=1` | (R sur `CONFIG_KEXEC`) | 🟡 | BP-028 le traite en compile-time ; STC le fait en runtime (contrôle apparenté) |
| — `kernel.pid_max`, `perf_cpu_time_max_percent`, `perf_event_max_sample_rate`, `panic_on_oops` | R9 | ⚪ | Réglages R9 non repris par STC |
| — `kernel.modules_disabled=1` | R10 | ⚪ | Non implémenté (casse le chargement dynamique — à évaluer) |

### `relics/nixos/hardening/network.nix`

| Réglage STC | Règle ANSSI | Statut | Note |
|---|---|---|---|
| `net.ipv4.conf.*.rp_filter` | R12 | ✅ | option `strictReversePathFilter` |
| `net.ipv4.conf.*.accept_redirects=0` | R12 | ✅ | + IPv6 |
| `net.ipv4.conf.*.secure_redirects=0` | R12 | ✅ | |
| `net.ipv4.conf.*.send_redirects=0` | R12 | ✅ | |
| `net.ipv4.icmp_ignore_bogus_error_responses=1` | R12 | ✅ | |
| `net.ipv4.tcp_syncookies=1` | R12 | ✅ | |
| `net.ipv4.icmp_echo_ignore_broadcasts=1` | R12 | 🟡 | Bonne pratique, hors liste R12 stricte |
| — `ip_forward`, `accept_source_route`, `arp_*`, `route_localnet`, `tcp_rfc1337`, `bpf_jit_harden`, `accept_local`, `shared_media` | R12 | ⚪ | Réglages R12 non repris par STC |
| — désactivation IPv6 | R13 | ⚪ | STC garde IPv6 (lib générique) |

### `relics/nixos/hardening/filesystem.nix`

| Réglage STC | Règle ANSSI | Statut | Note |
|---|---|---|---|
| `/tmp` `nosuid,nodev,noexec` | R28 | ✅ | (noexec omis si `gaming=true`) |
| `/proc` `hidepid=2,nosuid,noexec,nodev` | R28 | ✅ | |
| `/dev/shm` `nosuid,nodev,noexec` | R28 | 🟡 | Même esprit ; hors table R28 explicite |
| — partitions séparées `/boot /var /home /usr /opt /srv /var/log /var/tmp` | R28 | ⚪ | STC ne fait pas le partitionnement complet (rôle du schematic/disko) |

### `relics/nixos/hardening/ssh.nix`

| Réglage STC | Règle ANSSI | Statut | Note |
|---|---|---|---|
| `PermitRootLogin no`, `PasswordAuthentication no`, KexAlgorithms/Ciphers/Macs… | — | ⚪ | **Hors périmètre BP-028** : la config sshd relève du guide ANSSI *« Recommandations pour un usage sécurisé d'(Open)SSH »*, pas de BP-028 |

---

## Atomic Steps

### Step 1: Annoter les modules hardening avec les références ANSSI-BP-028

**Description :** Ajouter, à côté de chaque réglage, un commentaire `# ANSSI-BP-028
Rxx` (voir matrice). Pour `ssh.nix`, un commentaire indiquant que sshd est hors
BP-028 (guide OpenSSH séparé). Pour `kexec_load_disabled`, noter le compile-time
vs runtime. Commentaires uniquement — aucune option modifiée.

**Files changed:** les 4 fichiers `relics/nixos/hardening/*.nix`

**Verification:**
```bash
nix develop --command just fmt-check
nix develop --command just lint
nix flake check --no-write-lock-file
grep -rn "ANSSI-BP-028" relics/nixos/hardening/
```

**Commit:** `docs(hardening): annotate rules with ANSSI-BP-028 references`

---

### Step 2: Section doc `reference/` + matrice de conformité (EN + FR)

**Description :** Créer `docs/src/content/docs/{en,fr}/reference/anssi-bp-028.md`
avec la matrice ci-dessus (statuts ✅/🟡/⚪), une intro sur le périmètre et une note
honnête sur SSH (hors BP-028) et le partitionnement (rôle du schematic). Enregistrer
une section « Reference / Référence » dans la sidebar `docs/astro.config.mjs`.

**Files changed:**
- `docs/src/content/docs/en/reference/anssi-bp-028.md`
- `docs/src/content/docs/fr/reference/anssi-bp-028.md`
- `docs/astro.config.mjs`

**Verification:**
```bash
bash scripts/check-docs-parity.sh
cd docs && nix develop .#docs --command npm run build
```

**Commit:** `docs(reference): add ANSSI-BP-028 compliance matrix (EN + FR)`

---

## Quality Gates

- [ ] `nix flake check` vert ; `just fmt-check` + `just lint` propres
- [ ] `grep ANSSI-BP-028 relics/nixos/hardening/` : les 4 fichiers annotés
- [ ] `docs-parity` OK ; build Astro OK ; section Reference visible EN+FR
- [ ] Commits atomiques (annotations code / doc reference)

## Hors périmètre (roadmap)

- Reprendre des réglages R9/R10/R12 manquants = **évolution du hardening**, pas ce
  plan (ce plan *documente l'existant*, il ne le change pas).
- Le mapping du volet matériel (Secure Boot/TPM2/FIDO2) viendra en `reference/`
  au **plan 4**.
