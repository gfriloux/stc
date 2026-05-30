---
title: Hardening
description: Four hardening relics — kernel, network, filesystem, and SSH — plus the cogitator-hardening shortcut.
---

STC provides four independent hardening relics. Each addresses a distinct attack
surface and can be enabled individually.

## Kernel Hardening

**Module:** `stc.nixosModules.relics-hardening-kernel`

**Enable option:** `stc.hardening.kernel.enable`

Applies sysctl parameters that reduce the kernel attack surface:

| Category | What it does |
|----------|-------------|
| Memory layout | Full ASLR (`randomize_va_space = 2`), hide kernel pointers (`kptr_restrict = 2`), restrict dmesg |
| Unprivileged capabilities | Block eBPF, perf, and user namespace creation for unprivileged users |
| kexec / SysRq | Disable kexec (kernel replacement attack vector), disable SysRq |
| Core dumps | Disable entirely — core dumps can expose secrets and private keys |
| Filesystem | Protect hardlinks, symlinks, FIFOs, and regular files from abuse |

Core dumps are also disabled via PAM resource limits (`security.pam.loginLimits`) as
belt-and-suspenders.

## Network Hardening

**Module:** `stc.nixosModules.relics-hardening-network`

**Enable option:** `stc.hardening.network.enable`

Applies network sysctl hardening only. Does **not** manage the firewall — use
`networking.firewall` or your own nftables/iptables rules for port control.

Sysctl parameters applied:

| Category | What it does |
|----------|-------------|
| Anti-spoofing | Reverse path filtering on all interfaces |
| Redirect rejection | Ignores ICMP redirects in all directions, disables sending redirects |
| ICMP abuse | Ignores broadcast pings and bogus error responses |
| SYN flood | Enables SYN cookies |

:::note[Firewall is your responsibility]
This relic hardens the kernel network stack. Firewall rules (open ports, Docker
networking, etc.) are not touched. This keeps the relic composable with Docker
and other container setups.
:::

## Filesystem Hardening

**Module:** `stc.nixosModules.relics-hardening-filesystem`

**Enable option:** `stc.hardening.filesystem.enable`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.hardening.filesystem.tmpSize` | string | `"2G"` | Maximum size of the /tmp tmpfs |

Mounts three filesystems with restrictive options:

| Mount | What changes |
|-------|-------------|
| `/tmp` | tmpfs with `nosuid,noexec,nodev`, size-capped |
| `/proc` | `hidepid=2,gid=proc` — users only see their own processes; system services retain access via the `proc` group |
| `/dev/shm` | tmpfs with `nosuid,noexec,nodev`, capped at 256 MiB |

The `proc` group is created automatically. `systemd-logind` is added to it so
session management keeps working.

The `/tmp noexec` mount prevents attackers from writing and executing code in a
world-writable directory — a classic exploitation vector.

## SSH Hardening

**Module:** `stc.nixosModules.relics-hardening-ssh`

**Enable option:** `stc.hardening.ssh.enable`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.hardening.ssh.allowedTCPForwarding` | bool | `false` | Allow TCP forwarding |

Configures OpenSSH with:
- Password authentication disabled (keys only)
- Root login disabled
- MaxAuthTries: 3, LoginGraceTime: 20s
- Idle session timeout: 10 minutes (2 × 300s)
- X11, agent forwarding, tunneling, gateway ports: all disabled
- Strong ciphers: ChaCha20-Poly1305, AES-256-GCM, AES-128-GCM
- ETM MACs only: HMAC-SHA2-512-etm, HMAC-SHA2-256-etm
- Key exchange: curve25519-sha256, DH group 16

## Usage Example

Individual relics:

```nix
modules = [
  stc.nixosModules.relics-hardening-kernel
  stc.nixosModules.relics-hardening-network
  stc.nixosModules.relics-hardening-filesystem
  stc.nixosModules.relics-hardening-ssh
  ./configuration.nix
];

# configuration.nix
{
  stc.hardening.kernel.enable = true;
  stc.hardening.network.enable = true;
  stc.hardening.filesystem.enable = true;
  stc.hardening.filesystem.tmpSize = "4G";
  stc.hardening.ssh.enable = true;

  # Firewall is managed separately — open ports here as needed:
  networking.firewall.allowedTCPPorts = [ 22 80 443 ];
}
```

## The cogitator-hardening Shortcut

For the common case of enabling all four relics with defaults, use
[`cogitator-hardening`](/en/cogitator/hardening/). One option instead of four:

```nix
modules = [ stc.nixosModules.cogitator-hardening ];

# configuration.nix
{ stc.hardening.enable = true; }
```

The cogitator does not prevent you from tuning individual options afterward —
`stc.hardening.filesystem.tmpSize` and `stc.hardening.ssh.allowedTCPForwarding`
remain configurable.
