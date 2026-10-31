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
| R33 | Accountability of administration actions |
| R73 | Log system activity with auditd |

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
| `/var/tmp` `nosuid,nodev,noexec` | R28 | ✅ | Self-bind, stays on disk; `noexec` dropped when `gaming=true`; opt-out `varTmp.enable`; persisting it through impermanence is refused by an assertion |
| `/home` `nosuid,nodev` | R28 | ⚪ | Only when `/home` is a separate mount — not the case on STC's layouts; documented in the hardening page |
| `/dev/shm` `nosuid,nodev,noexec` | R28 | 🟡 | Same rationale; not in the R28 table |
| Separate `/boot /var /home /usr /opt /srv /var/log /var/tmp` partitions | R28 | ⚪ | STC does not partition — that is the schematic's disko layout, not a relic |

## `relics.hardening.scheduler`

Restricting `cron` and `at` to an allowlist is **out of ANSSI-BP-028 scope** —
no rule in the guide covers scheduler access. The relic exists on its own merit,
and this section records that so no reader goes looking for the matching rule.

The item comes from the CIS ~2.4.1.x family, which STC treats as informative
only (see *Why not CIS?* below). What makes it worth code rather than advice is
a NixOS-specific trap: `services.cron.enable` defaults to
`mkDefault (allFiles != [])`, so a third-party module setting
`services.cron.systemCronJobs` starts the daemon without the consumer asking —
and the NixOS module's own `preStart` opens it to every local user by touching
an empty `/var/cron/cron.deny`. Upstream vixie cron is closed by default; the
NixOS module reverses that. `atd` does the same with `/etc/at/at.deny`.

The relic writes `/var/cron/cron.allow` and `/etc/at/at.allow` — the paths NixOS
actually reads, not the `/etc/cron.allow` and `/etc/at.allow` that RHEL-derived
baselines cite. It enables no scheduler and is inert where none runs.

## `relics.hardening.audit`

R73 is a **minimal-level** rule: system activity is logged through auditd. The
guide follows it with an example `audit.rules`; STC's baseline takes part of
it, and the gaps are deliberate.

| STC setting | Rule | Status | Note |
|-------------|------|--------|------|
| auditd running, rules loaded at boot | R73 | ✅ | `audit=1` on the kernel command line; the proving checks `enabled 1`, not just the daemon |
| Module load/unload (`init_module`, `finit_module`, `delete_module`) | R73 | ✅ | The guide's `-w /sbin/insmod` watches are pointless on NixOS — no `/sbin`, `kmod` lives in the store; the syscalls catch every loader |
| `mount`, `umount2` | R73 | 🟡 | Filtered on `auid!=unset`: unfiltered, systemd's per-unit credential unmounts flood the log. Mounts from a login session, `sudo` included, are recorded |
| `-w /etc/ -p wa` | R73 | 🟡 | Narrowed to the identity files and sudoers (keys `identity`, `scope`). Add the guide's line through `security.audit.rules` if you want all of `/etc` |
| `ioperm`, `modify_ldt`, `get_kernel_syms`, `ptrace`, `prctl` | R73 | ⚪ | Not in the baseline. `prctl` is called by ordinary programs all the time; `get_kernel_syms` no longer exists on current kernels |
| File creation/deletion and `EACCES` monitoring | R73 | ⚪ | Not in the baseline; the guide itself warns about the performance cost |
| `-e 2` (locked configuration) | R73 | 🟡 | Opt-in through `immutable = true`: locked, a `nixos-rebuild switch` that changes the rules fails until reboot |
| `execve`/`execveat` of setuid programs from a login session (key `user_emulation`) | R33 | 🟡 | The guide's strongest form logs **every** `execve`; STC logs privilege changes only. Commands run through sudo are also in the journal (`journalctl -t sudo`, see below) |

Login and logout records need no rule: libpam emits `USER_START` and
`USER_END` itself. And no watch sits under `/var`: rules load before `/var/log`
exists, and one rule that fails disables all auditing — see the
[relic page](/stc/en/relics/hardening/#audit).

## `relics.hardening.ssh`

SSH hardening (`PermitRootLogin no`, `PasswordAuthentication no`, modern
KexAlgorithms/Ciphers/Macs, and `systemAuthorizedKeysOnly` restricting the
authorized-keys search path to `/etc/ssh/authorized_keys.d/%u`) is **out of
ANSSI-BP-028 scope**. sshd configuration is covered by a separate ANSSI guide,
*Recommandations pour un usage sécurisé d'(Open)SSH*. It is listed here only to
be explicit about the boundary — no `Rxx` reference is invented for it.

## Why there is no `relics.hardening.sudo`

CIS ~5.3.x asks for `Defaults use_pty` and a dedicated sudo `logfile`. Neither
becomes a relic. The reason is a measurement rather than a preference, and it is
recorded here so the gap is not raised again as a finding.

| CIS 5.3.x item | Measured state on NixOS | Source |
|---|---|---|
| `Defaults use_pty` | Already the default | sudo enabled it by default in **1.9.14** — `NEWS`: *"The `use_pty` sudoers option is now enabled by default. To restore the historic behavior … add `Defaults !use_pty`"*. nixpkgs ships **1.9.17p2** |
| `Defaults use_pty` under sudo-rs | Already the default | `sudoers(5)` of sudo-rs 0.2.14, entry `use_pty`: *"This flag is on by default"* |
| nixpkgs turning it off | Never | `grep -rn "use_pty"` over nixpkgs' `nixos/` tree returns nothing |
| dedicated `logfile` | Absent, and declined | sudo already logs every invocation to `authpriv`, which journald collects: `journalctl -t sudo` yields `TTY=`, `PWD=`, `USER=` and `COMMAND=` per call |
| dedicated `logfile` under sudo-rs | Not expressible | `sudoers(5)` of sudo-rs: *"sudo-rs logs events via syslog(3)"* — the implementation has no `logfile` setting at all |

A relic writing `Defaults use_pty` would therefore change no behaviour on any
host STC can build. It would read as hardening — in the consumer's configuration
and in this very matrix — while doing nothing, which is the failure mode this
page exists to prevent. The only host where the setting would bite is one pinned
to sudo older than 1.9.14, and that pin is the consumer's choice, not something a
relic should paper over.

The `logfile` half is a genuine absence and is still declined. The journal is
already bounded by `services.journald` retention; a `/var/log/sudo.log` is
rotated by nothing on NixOS and grows until the disk is full. The accountability
the control asks for is delivered by the journal entries above, so a second,
unbounded copy of them buys nothing and costs a server its disk.

A consumer who must satisfy the control literally can still do it per host,
without STC:

```nix
security.sudo.extraConfig = "Defaults logfile=/var/log/sudo.log";
```

Note that `security.sudo.extraConfig` is a `lines` option: definitions from
several modules concatenate, and for a given setting the last `Defaults` line
sudo reads is the one that applies. That ordering is the second reason this does
not belong in a relic — a relic cannot promise its line wins.

Tracked as [issue #37](https://github.com/gfriloux/stc/issues/37), closed on this
measurement.

## Why there is no `relics.networking.ntp`

CIS ~2.1.x asks for an explicit, validated time source rather than undocumented
defaults. The proposal was a relic exposing `enable` plus a `servers` option,
defaulting to `services.timesyncd.enable = true`. Measured against the locked
nixpkgs, every part of it already exists upstream, so no relic is added.

| Proposed behaviour | Measured state | How it was measured |
|---|---|---|
| `services.timesyncd.enable = true` | Already `true` — on a bare node and on all three schematics, with no STC line anywhere (`grep -rn "timesyncd\|chrony" relics/ cogitator/ schematics/` finds nothing but the AWS relic's `timeServers`) | `nix eval` of `config.services.timesyncd.enable` per schematic |
| …and still true with no servers | Still `true` with `networking.timeServers = []`: the unit runs, wanted by `sysinit.target` | `nix-instantiate --eval` on a bare node with the list forced empty |
| …and overridable | `services.timesyncd.enable = false` on a plain definition is accepted, and drops the unit and `/etc/systemd/timesyncd.conf` — the upstream default is a `mkDefault`, so no `mkForce` is needed | same probe, with `enable = false` |
| a `servers` option | `services.timesyncd.servers` exists upstream (default `null`) and writes `NTP=` | `nix eval` of `options.services.timesyncd` → `enable`, `servers`, `fallbackServers`, `settings` |
| picking a different implementation | `services.chrony.enable` and `services.ntp.enable` are both upstream options, both `false` here | same |

A relic would therefore be an alias for three upstream options, and `DESIGN.md`
has no room for a relic that renames what nixpkgs already exposes. The time
source is set, per host, with one upstream line:

```nix
# authoritative source, highest priority short of systemd-networkd
services.timesyncd.servers = ["ntp.internal.example"];
```

### The trap this ruling avoids

`networking.timeServers` does **not** set the authoritative server. It feeds
`services.timesyncd.fallbackServers`, which renders as `FallbackNTP=`. The
rendered file on `schematics/local-vm` is:

```ini
[Time]
FallbackNTP=0.nixos.pool.ntp.org 1.nixos.pool.ntp.org 2.nixos.pool.ntp.org 3.nixos.pool.ntp.org
```

`timesyncd.conf(5)`, read from the systemd build this flake locks, is explicit
about what that means: *"Any per-interface NTP servers obtained from
`systemd-networkd.service(8)` take precedence over this setting, as do any
servers set via `NTP=` above. This setting is hence only relevant if no other
NTP server information is known."*

So a relic whose `servers` option wired `networking.timeServers` — the obvious
implementation — would hand the consumer an option that reads as *"this is my
time source"* while writing the lowest-priority field, silently losing to any
NTP server a DHCP lease happens to advertise. That is the same failure mode as
the sudo entry above: configuration that reads as control and exercises none.

### Where STC does set a time server, and why it is a fallback

`relics/nixos/aws.nix` sets `networking.timeServers = ["169.254.169.123"]`, the
AWS-internal NTP endpoint, so `schematics/aws-ami` renders
`FallbackNTP=169.254.169.123`. Fallback is the right level there and is a
deliberate choice: EC2 advertises that same endpoint over DHCP, so the normal
path does not depend on this line at all — it covers the instance whose DHCP
lease carries no NTP option. Pinning it as `NTP=` instead would override a
consumer running an authoritative time server inside their own VPC, which is a
decision STC has no business making for them.

### Not covered, and named as such

Neither this ruling nor any relic gives you **authenticated** time.
`systemd-timesyncd` implements no NTS (RFC 8915); only `chronyd` does. A host
whose threat model includes an attacker on the network path shifting its clock —
to stall certificate expiry checks or to muddy audit timestamps — needs
`services.chrony` with NTS servers, which is a different implementation and a
product decision, not a wrapper. No issue is opened for it, so that it is not
mistaken for planned work.

Nothing here is covered by a proving, and cannot be: `qemu-vm.nix:1489` in the
locked nixpkgs sets `services.timesyncd.enable = false` for every VM the test
driver builds, so no `nixosTest` renders a `timesyncd.conf` at all. The
measurements above are evaluation-level, which is where the whole question
lives.

This section claims no `Rxx` reference. ANSSI-BP-028 was not consulted for it:
the guide's PDF is served behind an anti-bot filter that refused automated
retrieval, so no rule number is asserted either way. The ruling does not depend
on one — the relic would be an alias whatever ANSSI says about clocks.

Tracked as [issue #38](https://github.com/gfriloux/stc/issues/38), closed on
these measurements.
