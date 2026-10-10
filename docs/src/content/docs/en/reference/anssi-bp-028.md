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

## Why not CIS?

CIS publishes its Benchmarks per distribution — Ubuntu, RHEL, Debian, Amazon
Linux — and there is no CIS Benchmark for NixOS. STC therefore makes **no claim
of CIS compliance**, and the overlap in controls should not suggest otherwise:
the kernel and network sysctl, SSH, the module blacklist and the filesystem
mount options do cover much of what CIS Level 1/2 asks for, but that mapping is
informative, never normative. ANSSI-BP-028 is the baseline; CIS is a point of
comparison.

Gaps surfaced by comparing STC against CIS Level 1/2 are tracked on GitHub under
the [`compliance-cis`](https://github.com/gfriloux/stc/labels/compliance-cis)
label.

## Non-goals

No relic configures a password-quality or account-lockout policy (`pam_pwquality`,
`pam_faillock`, password expiration). SSH is keys-only, so there is no remote
password to guess, and the schematics run `users.mutableUsers = false`, which
leaves those PAM controls nothing to arbitrate. The residual risk on local console
login is documented — with the reasoning and the escape hatch — in
[`SECURITY_POLICY.md`](https://github.com/gfriloux/stc/blob/main/SECURITY_POLICY.md)
under *Threat model and non-goals*.

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
| `kernel.panic_on_oops=1` | R9 | ✅ | Paired with `kernel.panic=30` — see below |
| `kernel.pid_max` | R9 | ✅ | Satisfied without STC setting anything: systemd's `sysctl.d/50-pid-max.conf` gives `4194304`, far above R9's `65536`. Asserted as a floor in `provings/hardening.nix` |
| `kernel.perf_cpu_time_max_percent`, `kernel.perf_event_max_sample_rate` | R9 | ⚪ | Evaluated, not adopted — see below |
| `kernel.modules_disabled=1` | R10 | ⚪ | Full lockdown not implemented — breaks on-demand module loading. See `relics.hardening.modules` for the soft form (targeted blacklist) |

### On `panic_on_oops` and the reboot delay

An oops — `Oops:` or `BUG:` in `dmesg` — is a genuine kernel fault. By default
the kernel kills the faulting task and carries on in a state it cannot vouch
for. Several exploitation techniques tolerate, or deliberately provoke, a stream
of oopses (KASLR brute-force, heap spraying), which makes every survived oops a
free retry for the attacker. `panic_on_oops=1` ends the retry loop.

R9 stops there, but `panic_on_oops=1` on its own *freezes* the machine, because
`kernel.panic` defaults to `0` — wait forever. On a headless node that means no
return without console access. STC therefore also sets `kernel.panic=30`: the
machine still fails closed, then reboots. The delay is STC's addition, not an
R9 requirement. To keep a frozen machine for post-mortem analysis, override it:

```nix
boot.kernel.sysctl."kernel.panic" = lib.mkForce 0;
```

Do not confuse this with `kernel.panic_on_warn`, which reacts to `WARN_ON()` —
the `WARNING: ... at <file>:<line>` traces, a developer assertion rather than a
fault. A benign driver quirk emits those, so panicking on them would trade real
availability for nothing. ANSSI does not ask for it; STC does not set it.

To gauge the risk on a given host before enabling the relic, read the kernel's
own taint flags:

```console
$ cat /proc/sys/kernel/tainted
```

Bit 7 (value `128`, `TAINT_DIE`) is set once an oops or `die()` has occurred
since boot. If it stays clear on your workload, `panic_on_oops=1` costs nothing
in practice. Bit 9 (`512`) only records a `WARNING`, which this setting ignores.

### On the two perf rate limits

R9 asks for `perf_cpu_time_max_percent=1` and `perf_event_max_sample_rate=1`.
STC sets neither, for two reasons. `perf_event_paranoid=3` above already denies
perf to unprivileged users, so these two only throttle root's own profiling —
and root is trusted in STC's threat model, so this buys no confidentiality.
Second, the kernel already self-regulates: when the sampling NMI handler gets
expensive it lowers the rate on its own, visibly so in `dmesg`:

```
perf: interrupt took too long (4993 > 4967), lowering kernel.perf_event_max_sample_rate to 40000
```

A hard-coded `1` would replace that adaptive control with a value 40000× lower
and make profiling useless on a machine STC may well be asked to debug.

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
| `net.ipv4.conf.*.log_martians=1` | R12 | ✅ | Forensic signal only — `rp_filter` already drops the packets |
| `net.ipv4.conf.*.arp_ignore=1`, `arp_announce=2` | R12 | 🟡 | Opt-in via `strictArp` (off by default; breaks multi-homed / Docker) |
| `net.ipv4.icmp_echo_ignore_broadcasts=1` | R12 | 🟡 | Good practice, beyond the strict R12 list |
| `ip_forward`, `route_localnet`, `accept_local`, `shared_media` | R12 | ⚪ | R12 settings STC does not set |
| `net.ipv6.conf.*.accept_ra=0` | R13 | 🟡 | Opt-in via `strictIpv6RouterAdvertisements` (off by default; strands SLAAC hosts). A partial step in R13's direction, not IPv6 removal |
| Disable IPv6 | R13 | ⚪ | STC keeps IPv6 (generic library) |

## `relics.hardening.modules`

| STC setting | Rule | Status | Note |
|-------------|------|--------|------|
| Blacklist `firewire-core/ohci/sbp2` (DMA) | R10 | 🟡 | Soft form of R10 — targeted blacklist, not the full `modules_disabled` lockdown |
| Blacklist `dccp`, `sctp`, `rds`, `tipc` (rare protocols) | R10 | 🟡 | Same rationale |
| Blacklist `cramfs`, `freevxfs`, `jffs2`, `hfs`, `hfsplus` (legacy filesystems) | R10 | 🟡 | Same rationale. `udf` and `usb-storage` left to `extraBlacklist` — both still have legitimate uses |

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
