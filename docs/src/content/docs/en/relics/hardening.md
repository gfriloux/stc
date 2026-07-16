---
title: Hardening
description: Five hardening relics — kernel, network, filesystem, SSH, and module blacklist — plus the cogitator-hardening shortcut.
---

STC provides five independent hardening relics. Each addresses a distinct attack
surface and can be enabled individually.

## Kernel Hardening

**Module:** `stc.nixosModules.relics-hardening-kernel`

**Enable option:** `stc.relics.hardening.kernel.enable`

Applies sysctl parameters that reduce the kernel attack surface:

| Category | What it does |
|----------|-------------|
| Memory layout | Full ASLR (`randomize_va_space = 2`), hide kernel pointers (`kptr_restrict = 2`), restrict dmesg |
| Unprivileged capabilities | Block eBPF and perf for unprivileged users; restrict ptrace to direct children (`yama.ptrace_scope = 1`) |
| kexec / SysRq | Disable kexec (kernel replacement attack vector), disable SysRq |
| Core dumps | Disable entirely — core dumps can expose secrets and private keys |
| Filesystem | Protect hardlinks, symlinks, FIFOs, and regular files from abuse |

Core dumps are disabled via `systemd.coredump.enable = false` and PAM resource
limits (`security.pam.loginLimits`) as belt-and-suspenders.

## Network Hardening

**Module:** `stc.nixosModules.relics-hardening-network`

**Enable option:** `stc.relics.hardening.network.enable`

Applies network sysctl hardening only. Does **not** manage the firewall — use
`networking.firewall` or your own nftables/iptables rules for port control.

Sysctl parameters applied:

| Category | What it does |
|----------|-------------|
| Anti-spoofing | Reverse path filtering on all interfaces |
| Redirect rejection | Ignores ICMP redirects in all directions, disables sending redirects |
| Source routing | Rejects source-routed packets (IPv4 + IPv6) |
| ICMP abuse | Ignores broadcast pings and bogus error responses |
| SYN flood | Enables SYN cookies; TIME_WAIT assassination protection (`tcp_rfc1337`) |
| eBPF JIT | Hardens the JIT against spraying attacks (`bpf_jit_harden = 2`) |

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.hardening.network.strictReversePathFilter` | bool | `true` | Strict (`1`) reverse-path filtering. Set `false` for loose (`2`) on asymmetric-routing / multi-homed / WireGuard hosts where strict mode drops legitimate return traffic. |
| `stc.relics.hardening.network.strictArp` | bool | `false` | ARP hardening (`arp_ignore=1`, `arp_announce=2`). Off by default: can break multi-homed hosts, Linux bridges, and Docker networking. Enable only on single-homed hosts. |

:::note[Firewall is your responsibility]
This relic hardens the kernel network stack. Firewall rules (open ports, Docker
networking, etc.) are not touched. This keeps the relic composable with Docker
and other container setups.
:::

## Filesystem Hardening

**Module:** `stc.nixosModules.relics-hardening-filesystem`

**Enable option:** `stc.relics.hardening.filesystem.enable`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.hardening.filesystem.tmpSize` | string | `"2G"` | Maximum size of the /tmp tmpfs |
| `stc.relics.hardening.filesystem.shmSize` | string | `"256M"` | Maximum size of the /dev/shm tmpfs |
| `stc.relics.hardening.filesystem.gaming` | bool | `false` | Remove `noexec` from /tmp and /dev/shm — required for Wine/Proton and DXVK |

Mounts three filesystems with restrictive options:

| Mount | What changes |
|-------|-------------|
| `/tmp` | tmpfs with `nosuid,noexec,nodev`, size-capped — `noexec` omitted when `gaming = true` |
| `/proc` | `hidepid=2,gid=proc` — users only see their own processes; system services retain access via the `proc` group |
| `/dev/shm` | tmpfs with `nosuid,noexec,nodev`, size-capped — `noexec` omitted when `gaming = true` |

The `proc` group is created automatically. `systemd-logind` is added to it so
session management keeps working.

:::caution[hidepid and desktops / monitoring]
`hidepid=2` also hides other users' processes from polkit, user D-Bus agents and
several Prometheus exporters, which can make them misbehave. Only `systemd-logind`
is wired into the `proc` group out of the box. When you compose filesystem
hardening with a desktop (e.g. `cogitator-plasma`) or process exporters, add the
affected services to the `proc` group via `systemd SupplementaryGroups`, or leave
filesystem hardening off on those hosts. The relic emits a build warning when it
detects a desktop alongside this hardening.
:::

The `/tmp noexec` mount prevents attackers from writing and executing code in a
world-writable directory — a classic exploitation vector.

:::caution[Wine, Proton, and DXVK]
Wine and Proton extract and run binaries under `/tmp`. DXVK and VKD3D-Proton
map executable code into `/dev/shm`. Set `stc.relics.hardening.filesystem.gaming = true`
on gaming machines and raise `shmSize` to at least `2G` for heavy workloads.
The `/proc` hardening is unaffected.
:::

## SSH Hardening

**Module:** `stc.nixosModules.relics-hardening-ssh`

**Enable option:** `stc.relics.hardening.ssh.enable`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.hardening.ssh.allowedTCPForwarding` | bool | `false` | Allow TCP forwarding |
| `stc.relics.hardening.ssh.perSourcePenalties` | string | `"crash:3600s authfail:3600s max:86400s"` | sshd `PerSourcePenalties` — rate-limits misbehaving source addresses with escalating blocks. Set to `"no"` to disable. |

Configures OpenSSH with:
- Password authentication disabled (keys only)
- Root login disabled
- MaxAuthTries: 3, LoginGraceTime: 20s
- Per-source penalties: rate-limit auth failures / crashes by source address
- Idle session timeout: 10 minutes (2 × 300s)
- X11, agent forwarding, tunneling, gateway ports: all disabled
- Strong ciphers: ChaCha20-Poly1305, AES-256-GCM, AES-128-GCM
- ETM MACs only: HMAC-SHA2-512-etm, HMAC-SHA2-256-etm
- Key exchange: post-quantum hybrids first (mlkem768x25519-sha256,
  sntrup761x25519-sha512), then curve25519-sha256 and DH group 16

:::caution[Requires OpenSSH ≥ 9.9]
The `mlkem768x25519-sha256` key exchange needs OpenSSH ≥ 9.9. The relic asserts
this at build time, so a consumer pinned (via `inputs.nixpkgs.follows`) to an
older nixpkgs gets a clear build error instead of an sshd that silently refuses
to start — which would lock you out. Upgrade nixpkgs, or override
`services.openssh.settings.KexAlgorithms` to drop the post-quantum kex.
:::

## Module Blacklist

**Module:** `stc.nixosModules.relics-hardening-modules`

**Enable option:** `stc.relics.hardening.modules.enable`

Blacklists high-risk and unused kernel modules to shrink the attack surface:

| Family | Modules | Why |
|--------|---------|-----|
| FireWire (DMA) | `firewire-core`, `firewire-ohci`, `firewire-sbp2` | A hostile device can read/write physical memory over the bus |
| Rare network protocols | `dccp`, `sctp`, `rds`, `tipc` | Almost never used on a normal host, yet a recurring source of kernel CVEs |

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.hardening.modules.extraBlacklist` | list of string | `[]` | Additional modules to blacklist, merged with the curated defaults (e.g. `[ "bluetooth" "uvcvideo" ]`) |

This is the *soft* form of ANSSI-BP-028 R10 (disable unused modules): a targeted
blacklist rather than the full `kernel.modules_disabled=1` lockdown, which would
break on-demand module loading and needs case-by-case evaluation.

:::caution[FireWire and rare protocols]
If a host genuinely needs FireWire (e.g. an audio interface) or one of the rare
protocols (SCTP for some telephony/SIP stacks), enable the other relics à la carte
instead of this one, or override `boot.blacklistedKernelModules`.
:::

## Usage Example

Individual relics:

```nix
modules = [
  stc.nixosModules.relics-hardening-kernel
  stc.nixosModules.relics-hardening-network
  stc.nixosModules.relics-hardening-filesystem
  stc.nixosModules.relics-hardening-ssh
  stc.nixosModules.relics-hardening-modules
  ./configuration.nix
];

# configuration.nix
{
  stc.relics.hardening.kernel.enable = true;
  stc.relics.hardening.network.enable = true;
  stc.relics.hardening.filesystem.enable = true;
  stc.relics.hardening.filesystem.tmpSize = "4G";
  stc.relics.hardening.ssh.enable = true;
  stc.relics.hardening.modules.enable = true;

  # Firewall is managed separately — open ports here as needed:
  networking.firewall.allowedTCPPorts = [ 22 80 443 ];
}
```

Gaming machine with hardening:

```nix
{
  stc.relics.hardening.kernel.enable = true;

  stc.relics.hardening.filesystem.enable = true;
  stc.relics.hardening.filesystem.gaming = true;  # allow exec in /tmp and /dev/shm
  stc.relics.hardening.filesystem.shmSize = "4G"; # DXVK/VKD3D need more than 256M

  stc.relics.hardening.network.enable = true;
  stc.relics.hardening.ssh.enable = true;
}
```

## The cogitator-hardening Shortcut

For the common case of enabling all five relics with defaults, use
[`cogitator-hardening`](/stc/en/cogitator/hardening/). One option instead of five:

```nix
modules = [ stc.nixosModules.cogitator-hardening ];

# configuration.nix
{ stc.cogitator.hardening.enable = true; }
```

The cogitator does not prevent you from tuning individual options afterward —
`stc.relics.hardening.filesystem.tmpSize` and `stc.relics.hardening.ssh.allowedTCPForwarding`
remain configurable.
