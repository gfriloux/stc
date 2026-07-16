---
title: ANSSI-BP-028 compliance
description: How STC's hardening maps to the ANSSI-BP-028 v2.0 GNU/Linux configuration guide.
sidebar:
  order: 0
---

STC's hardening relics are traceable to the French **ANSSI-BP-028 v2.0**
recommendations (*Configuration recommendations of a GNU/Linux system*,
03/10/2022). Each setting carries an inline `# ANSSI-BP-028 Rxx` reference in the
source; this page is the readable matrix.

This is a **fidelity map, not a certification**. It documents what the current
relics do — it does not claim STC is a compliant system. Full compliance also
requires disk partitioning, secrets management, and physical/boot security that
belong to the consumer's own flake and hardware.

**Status legend:** ✅ covered · 🟡 partial · ⚪ out of scope / not implemented.

## Relevant ANSSI-BP-028 rules

| Rule | Topic |
|------|-------|
| R9  | Kernel sysctl configuration |
| R10 | Disable kernel module loading |
| R11 | Yama LSM (`ptrace_scope`) |
| R12 | IPv4 network sysctl configuration |
| R13 | Disable IPv6 when unused |
| R14 | Filesystem sysctl configuration |
| R28 | Typical partitioning and mount options |

## `relics.hardening.kernel`

| STC setting | Rule | Status | Note |
|-------------|------|--------|------|
| `kernel.randomize_va_space=2` | R9 | ✅ | Full ASLR |
| `kernel.kptr_restrict=2` | R9 | ✅ | |
| `kernel.dmesg_restrict=1` | R9 | ✅ | |
| `kernel.perf_event_paranoid=3` | R9 | ✅ | Stricter than ANSSI (2) |
| `kernel.unprivileged_bpf_disabled=1` | R9 | ✅ | |
| `kernel.sysrq=0` | R9 | ✅ | |
| `kernel.yama.ptrace_scope=1` | R11 | ✅ | |
| `fs.suid_dumpable=0` (+ coredump off, PAM limit) | R14 | ✅ | |
| `fs.protected_hardlinks=1` | R14 | ✅ | |
| `fs.protected_symlinks=1` | R14 | ✅ | |
| `fs.protected_fifos=2` | R14 | ✅ | |
| `fs.protected_regular=2` | R14 | ✅ | |
| `kernel.kexec_load_disabled=1` | (kexec) | 🟡 | ANSSI disables kexec at compile time (`CONFIG_KEXEC` unset); STC uses the runtime sysctl |
| `pid_max`, `perf_cpu_time_max_percent`, `perf_event_max_sample_rate`, `panic_on_oops` | R9 | ⚪ | R9 settings STC does not set |
| `kernel.modules_disabled=1` | R10 | ⚪ | Full lockdown not implemented — breaks on-demand module loading. See `relics.hardening.modules` for the soft form (targeted blacklist) |

## `relics.hardening.network`

| STC setting | Rule | Status | Note |
|-------------|------|--------|------|
| `net.ipv4.conf.*.rp_filter` | R12 | ✅ | Via `strictReversePathFilter` |
| `net.ipv4.conf.*.accept_redirects=0` (+ IPv6) | R12 | ✅ | |
| `net.ipv4.conf.*.secure_redirects=0` | R12 | ✅ | |
| `net.ipv4.conf.*.send_redirects=0` | R12 | ✅ | |
| `net.ipv4.icmp_ignore_bogus_error_responses=1` | R12 | ✅ | |
| `net.ipv4.tcp_syncookies=1` | R12 | ✅ | |
| `net.ipv4.conf.*.accept_source_route=0` (+ IPv6) | R12 | ✅ | |
| `net.ipv4.tcp_rfc1337=1` | R12 | ✅ | TIME_WAIT assassination protection |
| `net.core.bpf_jit_harden=2` | R12 | ✅ | eBPF JIT hardening |
| `net.ipv4.conf.*.arp_ignore=1`, `arp_announce=2` | R12 | 🟡 | Opt-in via `strictArp` (off by default; breaks multi-homed / Docker) |
| `net.ipv4.icmp_echo_ignore_broadcasts=1` | R12 | 🟡 | Good practice, beyond the strict R12 list |
| `ip_forward`, `route_localnet`, `accept_local`, `shared_media` | R12 | ⚪ | R12 settings STC does not set |
| Disable IPv6 | R13 | ⚪ | STC keeps IPv6 (generic library) |

## `relics.hardening.modules`

| STC setting | Rule | Status | Note |
|-------------|------|--------|------|
| Blacklist `firewire-core/ohci/sbp2` (DMA) | R10 | 🟡 | Soft form of R10 — targeted blacklist, not the full `modules_disabled` lockdown |
| Blacklist `dccp`, `sctp`, `rds`, `tipc` (rare protocols) | R10 | 🟡 | Same rationale |

## `relics.hardening.filesystem`

| STC setting | Rule | Status | Note |
|-------------|------|--------|------|
| `/tmp` `nosuid,nodev,noexec` | R28 | ✅ | `noexec` dropped when `gaming=true` |
| `/proc` `hidepid=2` | R28 | ✅ | |
| `/dev/shm` `nosuid,nodev,noexec` | R28 | 🟡 | Same rationale; not in the R28 table |
| Separate `/boot /var /home /usr /opt /srv /var/log /var/tmp` partitions | R28 | ⚪ | STC does not partition — that is the schematic's disko layout, not a relic |

## `relics.hardening.ssh`

SSH hardening (`PermitRootLogin no`, `PasswordAuthentication no`, modern
KexAlgorithms/Ciphers/Macs) is **out of ANSSI-BP-028 scope**. sshd configuration
is covered by a separate ANSSI guide, *Recommandations pour un usage sécurisé
d'(Open)SSH*. It is listed here only to be explicit about the boundary.
