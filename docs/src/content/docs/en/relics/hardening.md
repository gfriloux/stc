---
title: Hardening
description: Eight hardening relics — kernel, network, filesystem, SSH, module blacklist, scheduler access, audit and firewall — plus the cogitator-hardening shortcut.
---

STC provides eight independent hardening relics. Each addresses a distinct attack
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
| Kernel faults | Panic on an oops (`panic_on_oops = 1`) and reboot 30 s later (`panic = 30`) instead of carrying on in a state the kernel cannot vouch for |
| Core dumps | Disable entirely — core dumps can expose secrets and private keys |
| Filesystem | Protect hardlinks, symlinks, FIFOs, and regular files from abuse |

Core dumps are disabled via `systemd.coredump.enable = false` and PAM resource
limits (`security.pam.loginLimits`) as belt-and-suspenders.

:::caution[Panicking on an oops is a real availability trade]
A kernel oops that the machine would previously have survived now takes it down
and reboots it. This only covers genuine faults (`Oops:` / `BUG:` in `dmesg`),
never the `WARNING: ... at <file>:<line>` traces that a benign driver quirk
emits. Check `cat /proc/sys/kernel/tainted` on the host: if bit 7 (`128`) never
lights up under your workload, no oops has occurred and the setting costs you
nothing. Keep a frozen machine for post-mortem instead of rebooting with
`boot.kernel.sysctl."kernel.panic" = lib.mkForce 0;` — and on a server profile,
also `stc.relics.serverSurvivability.panicReboot = false;`, whose `panic=30` on
the command line covers the boot before the sysctl applies. Full reasoning in
[ANSSI-BP-028 fidelity](/stc/en/reference/anssi-bp-028/).
:::

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
| Martian logging | Logs packets with an impossible source address (`log_martians`) |
| ICMP abuse | Ignores broadcast pings and bogus error responses |
| SYN flood | Enables SYN cookies; TIME_WAIT assassination protection (`tcp_rfc1337`) |
| eBPF JIT | Hardens the JIT against spraying attacks (`bpf_jit_harden = 2`) |

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.hardening.network.strictReversePathFilter` | bool | `true` | Strict (`1`) reverse-path filtering. Set `false` for loose (`2`) on asymmetric-routing / multi-homed / WireGuard hosts where strict mode drops legitimate return traffic. |
| `stc.relics.hardening.network.strictArp` | bool | `false` | ARP hardening (`arp_ignore=1`, `arp_announce=2`). Off by default: can break multi-homed hosts, Linux bridges, and Docker networking. Enable only on single-homed hosts. |
| `stc.relics.hardening.network.strictIpv6RouterAdvertisements` | bool | `false` | Refuse IPv6 Router Advertisements (`accept_ra=0`). Off by default: strands any SLAAC-addressed host. Enable where IPv6 is static or unused, so a neighbour on an untrusted segment cannot inject a prefix and a default route. |

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
| `stc.relics.hardening.filesystem.varTmp.enable` | bool | `true` | Remount /var/tmp onto itself with `nosuid,nodev,noexec` |
| `stc.relics.hardening.filesystem.gaming` | bool | `false` | Remove `noexec` from /tmp, /var/tmp and /dev/shm — required for Wine/Proton and DXVK |

Mounts four filesystems with restrictive options:

| Mount | What changes |
|-------|-------------|
| `/tmp` | tmpfs with `nosuid,noexec,nodev`, size-capped — `noexec` omitted when `gaming = true` |
| `/var/tmp` | bound onto itself with `nosuid,noexec,nodev` — stays on disk, `noexec` omitted when `gaming = true` |
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

### /var/tmp

`/var/tmp` is the other world-writable directory, so it gets the same three
flags. It is **bound onto itself** rather than onto the `/tmp` tmpfs: its data
stays where your layout puts it and keeps whatever persistence the layout gives
it, and the relic needs no knowledge of the disk layout. On a classic disk it
survives a reboot (its FHS purpose). On an impermanence host it lives on the
rolled-back root, so it is wiped at boot, as before: the mount creates the
directory if needed (`X-mount.mkdir`), then `systemd-tmpfiles` sets its `1777`
mode.

Persisting `/var/tmp` through impermanence (`extraDirectories` or
`environment.persistence`) is **refused by an assertion**: the persistence bind
mount would replace the hardened one and silently drop the three flags. Either
stop persisting it, or set `varTmp.enable = false` to accept `/var/tmp` without
them. Nix
builds are unaffected: `nix-daemon` builds under `/nix/var/nix/builds`.

If your layout already mounts `/var/tmp` (its own dataset or partition), the two
definitions conflict at evaluation. Set `varTmp.enable = false` and put the
flags on your own mount instead:

```nix
stc.relics.hardening.filesystem.varTmp.enable = false;
fileSystems."/var/tmp".options = [ "nosuid" "nodev" "noexec" ];
```

### /home

The relic does not touch `/home`: it cannot tell whether `/home` is a separate
mount, and on STC's own ZFS layouts it is not (only `/`, `/nix` and `/persist`
are). If `/home` is a separate mount in your layout, add the flags yourself:

```nix
fileSystems."/home".options = [ "nosuid" "nodev" ];
```

:::caution[Wine, Proton, and DXVK]
Wine and Proton extract and run binaries under `/tmp`. DXVK and VKD3D-Proton
map executable code into `/dev/shm`. `/var/tmp` follows `/tmp` for consistency.
Set `stc.relics.hardening.filesystem.gaming = true`
on gaming machines and raise `shmSize` to at least `2G` for heavy workloads.
The `/proc` hardening is unaffected.
:::

## SSH Hardening

**Module:** `stc.nixosModules.relics-hardening-ssh`

**Enable option:** `stc.relics.hardening.ssh.enable`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.hardening.ssh.allowedTCPForwarding` | bool | `false` | Allow TCP forwarding. Also drives `StreamLocalBindUnlink`, which only has an object when forwarding is allowed. |
| `stc.relics.hardening.ssh.allowedX11Forwarding` | bool | `false` | Allow X11 forwarding. Needed by a workstation forwarding a remote GUI app, and by a host that is also a Slurm client. |
| `stc.relics.hardening.ssh.allowedAgentForwarding` | bool | `false` | Allow SSH agent forwarding — hopping through a bastion with your own agent. |
| `stc.relics.hardening.ssh.allowedTunnel` | bool | `false` | Allow tun device forwarding (`PermitTunnel`). |
| `stc.relics.hardening.ssh.systemAuthorizedKeysOnly` | bool | `true` | Read authorized keys only from `/etc/ssh/authorized_keys.d/%u` — what the flake declares — never from `~/.ssh/authorized_keys`. **Can lock you out**; see below. |
| `stc.relics.hardening.ssh.perSourcePenalties` | string | `"crash:3600s authfail:3600s max:86400s"` | sshd `PerSourcePenalties` — rate-limits misbehaving source addresses with escalating blocks. Set to `"no"` to disable. |
| `stc.relics.hardening.ssh.banner` | null or lines | `null` | Pre-authentication warning banner text. The relic writes it to the store and points sshd `Banner` at that file. `null` writes no `Banner` directive at all. |

Configures OpenSSH with:
- Password authentication disabled (keys only)
- Root login disabled
- `LogLevel VERBOSE` — logs the fingerprint of the public key each accepted
  connection used. With keys-only authentication, that fingerprint is the only
  thing tying a session to a key, and therefore to a person.
- MaxAuthTries: 3, LoginGraceTime: 20s
- Per-source penalties: rate-limit auth failures / crashes by source address
- Idle session timeout: 10 minutes (2 × 300s)
- X11, agent forwarding, tunneling, gateway ports: all disabled
- Authorized keys read only from `/etc/ssh/authorized_keys.d/%u`
- `UseDns no` — no reverse-DNS round trip per connection. This one is the
  upstream default, not something the relic sets; it is listed because the
  question comes up.
- Strong ciphers: ChaCha20-Poly1305, AES-256-GCM, AES-128-GCM
- ETM MACs only: HMAC-SHA2-512-etm, HMAC-SHA2-256-etm
- Key exchange: post-quantum hybrids first (mlkem768x25519-sha256,
  sntrup761x25519-sha512), then curve25519-sha256 and DH group 16

:::danger[Read this before enabling on a host you cannot reach physically]
`systemAuthorizedKeysOnly` is on by default. It removes `~/.ssh/authorized_keys`
from sshd's search path, so **a key that is not declared in your configuration
stops working at the next switch.**

On a fully declarative host this changes nothing operationally: the module
already writes every declared key to `/etc/ssh/authorized_keys.d/<user>`, which
remains the one file sshd reads. What changes is that the flake becomes the
whole truth — which is the point. A service compromised under a user's account,
a careless container bind-mount or a sync tool can no longer grant itself
persistent SSH access invisibly.

Check before you deploy, not after:

```bash
# on the target host — every key that is about to stop working
sudo find /home /root -maxdepth 3 -name authorized_keys -exec ls -l {} +
```

Keep a second way in (console, out-of-band, a second session already open)
while you switch the first time.
:::

:::caution[Software that manages its own keys]
A whole class of software writes its own `authorized_keys` and loses every way
in under this option. **Git forges** are the obvious case, and the relic
refuses to build when it sees one:

```
stc.relics.hardening.ssh: systemAuthorizedKeysOnly removes ~/.ssh/authorized_keys
from sshd's search path, but services.gitea manages its own authorized_keys file
and would lose all SSH access. Either set
stc.relics.hardening.ssh.systemAuthorizedKeysOnly = false on this host, or append
the path the service needs to services.openssh.authorizedKeysFiles (it is a list
— definitions merge, so the system path is kept).
```

The assertion covers `services.gitea`, `services.forgejo`, `services.gitlab`,
`services.gitolite` and `services.gerrit`. **Treat that as a sample of the
class, not as the complete list** — anything expecting per-user key management
is affected and gets no build error: SFTP-only accounts, backup targets that
let the peer append its own key, home-grown provisioning that drops a key into
`~/.ssh`.

srvos disables the lockdown automatically for those services. STC does not: an
automatic exclusion weakens the hardening on a host where nobody decided to
weaken it. You get a failed build and two ways out instead — turn the option
off for the host, or append the one path you need:

```nix
# keeps the lockdown, adds a single extra location
services.openssh.authorizedKeysFiles = ["/etc/ssh/forge_keys/%u"];
```

`authorizedKeysFiles` is a list and definitions merge, so the system path stays
in place.
:::

:::note[The banner is opt-in]
Banner wording is legal, site-specific content — STC cannot write it for you, so
the default is `null` and no `Banner` directive is emitted until you set one:

```nix
stc.relics.hardening.ssh.banner = ''
  Authorized access only. All activity is logged.
'';
```

Already keeping the text in a file? `banner = builtins.readFile ./banner.txt;`.
:::

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
| Legacy filesystems | `cramfs`, `freevxfs`, `jffs2`, `hfs`, `hfsplus` | Drivers nothing on a normal host mounts, each one a parser reachable from removable media |

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.hardening.modules.extraBlacklist` | list of string | `[]` | Additional modules to blacklist, merged with the curated defaults (e.g. `[ "bluetooth" "uvcvideo" ]`) |

This is the *soft* form of ANSSI-BP-028 R10 (disable unused modules): a targeted
blacklist rather than the full `kernel.modules_disabled=1` lockdown, which would
break on-demand module loading and needs case-by-case evaluation.

### Not blacklisted by default: `udf` and `usb-storage`

The usual baselines also list `udf` (optical media) and `usb-storage`. Both stay
out of the defaults here, because both still have legitimate uses — mounting a
DVD/Blu-ray, installing from a USB stick — and because
`boot.blacklistedKernelModules` is a list: `extraBlacklist` adds to it, nothing
subtracts from it. A default that turns out wrong would leave no clean override.
On a host where neither is needed, put them in `extraBlacklist`:

```nix
stc.relics.hardening.modules.extraBlacklist = [ "udf" "usb-storage" ];
```

:::caution[FireWire, rare protocols, legacy filesystems]
If a host genuinely needs FireWire (e.g. an audio interface), one of the rare
protocols (SCTP for some telephony/SIP stacks), or one of the legacy filesystems
(`hfsplus` on a dual-boot Mac), enable the other relics à la carte instead of this
one, or override `boot.blacklistedKernelModules`.
:::

## Scheduler Access

**Module:** `stc.nixosModules.relics-hardening-scheduler`

**Enable option:** `stc.relics.hardening.scheduler.enable`

Restricts the classic job schedulers — `cron` and `at` — to an explicit
allowlist, `["root"]` by default.

This relic **never enables a scheduler**. Its whole configuration is guarded by
`mkIf config.services.cron.enable` and `mkIf config.services.atd.enable`, so it
is inert on a host that schedules with systemd timers — which is every STC
machine. It exists for the host that does run one of them, because nixpkgs
deliberately opens both to every local user:

| Upstream behaviour | Consequence |
|---|---|
| Vixie cron allows only root when neither `cron.allow` nor `cron.deny` exists | The NixOS module's `preStart` touches an empty `/var/cron/cron.deny` — "By default, allow all users to create a crontab" — which reverses that |
| `atd`'s `preStart` touches an empty `/etc/at/at.deny` | Same effect: nobody is denied, so everybody is allowed |

And cron can switch itself on: `services.cron.enable` defaults to
`mkDefault (allFiles != [])`, so any third-party module that sets
`services.cron.systemCronJobs` starts the daemon — open to everyone — without
the consumer ever asking for it. That case is the reason this relic is code
rather than a paragraph of advice.

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.hardening.scheduler.allowedUsers` | list of str | `[ "root" ]` | Users allowed to schedule jobs with `crontab` and `at`. Written to `/var/cron/cron.allow` and `/etc/at/at.allow`, both of which take precedence over the permissive `*.deny` the upstream modules create. |

Note the paths: NixOS uses `/var/cron/cron.allow` and `/etc/at/at.allow`, not
the `/etc/cron.allow` and `/etc/at.allow` that RHEL-derived baselines cite. A
host that writes the latter has restricted nothing.

A system crontab declared through `services.cron.systemCronJobs` is unaffected:
it runs from `/etc/crontab` as root and never goes through the per-user
`crontab` command this list gates.

:::caution[This can take crontab away from existing users]
If a host already runs cron — including through the auto-enable above — and
non-root users rely on `crontab`, enabling this relic refuses them. List them in
`allowedUsers`:

```nix
stc.relics.hardening.scheduler.allowedUsers = [ "root" "deploy" ];
```

Both allow files are rewritten from the Nix store on every activation, so a
hand-edited `/var/cron/cron.allow` will not survive a rebuild. That is the point
of declaring the allowlist here, but it will silently replace an allowlist
maintained by hand.
:::

## Audit

**Module:** `stc.nixosModules.relics-hardening-audit`

**Enable option:** `stc.relics.hardening.audit.enable`

Runs auditd with a baseline ruleset loaded at boot (ANSSI-BP-028 R73). It sits
on the upstream `security.audit` and `security.auditd` modules: the relic adds
the rules and two defaults, nothing else.

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.hardening.audit.enable` | bool | `false` | Enable auditd and the baseline ruleset |
| `stc.relics.hardening.audit.immutable` | bool | `false` | Lock the audit configuration until reboot (`auditctl -e 2`) |

The relic also sets `security.audit.backlogLimit = 8192` (`mkDefault`;
upstream is 1024), so the events emitted before auditd starts are not lost.
The kernel command line gains `audit=1 audit_backlog_limit=8192`.

**What is recorded** — search with `ausearch -i -k <key>`:

| Key | Rule | Records |
|-----|------|---------|
| `identity` | watch `/etc/passwd`, `/etc/group`, `/etc/shadow`, `/etc/gshadow` | Any write or attribute change |
| `scope` | watch `/etc/sudoers`, `/etc/sudoers.d` | Any write or attribute change |
| `user_emulation` | `execve`/`execveat` with `euid != uid`, from a login session | Running `sudo`, `su` or any setuid program |
| `kernel_modules` | `init_module`, `finit_module`, `delete_module` | Every module load and unload, udev's included |
| `mounts` | `mount`, `umount2`, from a login session | Mounts by a logged-in user, `sudo mount` included |

On x86_64 the three syscall rules also exist for the 32-bit syscall table
(`arch=b32`), the usual way around a 64-bit-only rule.

Logins and logouts need no rule. libpam itself (nixpkgs builds it with audit
support) emits `USER_AUTH`, `USER_START` and `USER_END` records for every PAM
stack, an SSH key login included: `ausearch -i -m USER_START`.

The two rules marked "from a login session" filter on `auid!=unset`. For
`mounts` it is a necessity: unfiltered, systemd unmounting
`/run/credentials/<unit>` on every unit start floods the log. For
`user_emulation` it is the usual baseline's form. A daemon that runs `mount`
or a setuid program on its own is therefore not recorded; anything done by a
user who logged in is, even through `sudo`, because the audit uid follows the
session.

:::danger[One bad rule turns all auditing off]
Upstream loads every rule with a single `auditctl -R` in
`audit-rules-nixos.service`, very early in boot, before `sysinit.target`. If
one line fails, the load stops, the unit turns auditing off on its way out,
and **auditd keeps running as if nothing happened**. The only trace is the
failed unit:

```bash
systemctl status audit-rules-nixos.service   # must be active
auditctl -s | head -1                         # must read "enabled 1" (2 with immutable)
```

A watch under `/var` is the classic way to get there: `/var/log` does not exist
yet at that point, and on an impermanence host it is a bind mount set up later.
That is why the baseline has no `wtmp` or `lastlog` watch. Keep your own
watches on paths that live on the root filesystem from the start, such as
`/etc`.
:::

**Adding rules.** Append to `security.audit.rules` directly. A plain
definition lands after the baseline; an exclusion (`-a never`) must come first
to take effect, so give it `lib.mkBefore`:

```nix
security.audit.rules = [
  "-w /etc/nixos -p wa -k nixos-config"
];
```

```nix
# Ignore everything uid 990 does, before the baseline rules see it.
security.audit.rules = lib.mkBefore [
  "-a never,exit -F uid=990"
];
```

Give uids as numbers. auditctl resolves a user name when it loads the rules,
and an unknown name — an account that does not exist yet that early in boot —
aborts the whole load.

**Logs.** Records go to `/var/log/audit/audit.log`. NixOS writes no rotation
settings and auditd's built-in defaults never rotate, so the relic sets five
files of 8 MiB (`security.auditd.settings.{max_log_file,num_logs,max_log_file_action}`,
all `mkDefault`): 40 MiB at most. On an impermanence host `/var/log` is
persisted, so the trail survives the rollback. journald also receives a copy
of every record (`journalctl _TRANSPORT=audit`); to keep audit records out of
the journal, set `systemd.sockets.systemd-journald-audit.enable = false;`.

**`immutable`.** With `immutable = true`, root can no longer change the rules
until the next reboot. A `nixos-rebuild switch` that changes them fails the
`audit-rules-nixos` unit, and the new rules apply only after a reboot. Turn it
on once the ruleset is settled, not while you are still tuning it. Set it
through this option rather than `security.audit.enable = "lock"`: the relic
writes that option itself, and a second definition conflicts.

## Firewall

**Module:** `stc.nixosModules.relics-hardening-firewall`

**Enable option:** `stc.relics.hardening.firewall.enable`

The NixOS firewall is on by default and drops every inbound connection to a
port nobody opened. This relic turns that default into a checked claim and
logs what the firewall refuses. It sits on upstream `networking.firewall` and
works the same on the iptables backend (the NixOS default) and on nftables
(`networking.nftables.enable = true`). Under firewalld, upstream translates the
logging option into firewalld's own `LogDenied`, with its own format: what
follows about log lines does not apply there.

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.hardening.firewall.enable` | bool | `false` | Assert the firewall is on and log refused connections |
| `stc.relics.hardening.firewall.logRefusedConnections` | bool | `true` | Log each refused inbound TCP connection to the kernel log |

What it does:

- **Two assertions.** `networking.firewall.enable` must be true, and neither
  ferm nor shorewall may be enabled: both disable the NixOS firewall unit while
  leaving that option true, and ferm's default ruleset lets everything in. A
  host in either case fails evaluation instead of claiming a hardening it does
  not have.
- **Refused connections logged**, which upstream does not do: every refused TCP
  SYN lands in the kernel log, IPv4 and IPv6 alike.

```bash
journalctl -k -g 'refused connection'
```

Only TCP connection attempts are logged. Refused UDP leaves no line; upstream's
`networking.firewall.logRefusedPackets` logs every refused packet, broadcasts
included, and is meant for debugging. Do not count on one line per attempt
under a scan either: a 200-port scan in a test produced only a handful.

:::note[Turning logging off]
Set `stc.relics.hardening.firewall.logRefusedConnections = false;`, not
`networking.firewall.logRefusedConnections`. The relic writes the upstream
option at normal priority, because nixpkgs' installation-device profile already
holds a `mkDefault false` on it and a second `mkDefault` would conflict; a
plain `false` of your own would conflict with the relic's.
:::

**Opening ports.** The relic owns no port list. Relics and consumers add their
own, and nothing in STC ever disables or flushes the firewall:

```nix
networking.firewall.allowedTCPPorts = [ 80 443 ];
networking.firewall.allowedUDPPorts = [ 51820 ];
```

Upstream services that take an `openFirewall` option open their port that way
(`services.openssh` does it by default, which is why SSH needs no line). The
traefik relics add 80 and 443 themselves.

**Your own ruleset instead.** If another layer filters this host's traffic — your
own nftables ruleset with the NixOS firewall off, ferm, shorewall, a cloud
security group alone — say so explicitly:

```nix
networking.firewall.enable = false;
stc.relics.hardening.firewall.enable = false;
```

**What it does not cover.**

- Ports published by Docker. Docker's DNAT and FORWARD rules sit ahead of
  `networking.firewall`, so a `-p 8080:80` container is reachable whatever the
  firewall says. That is what [`docker.guards`](/stc/en/relics/docker/#docker-guards) warns
  about.
- Rate limiting. SSH brute force is throttled by sshd's `PerSourcePenalties`
  (SSH hardening above), not by the firewall: a firewall rate limit would need
  one rule set per backend for the same effect.

## Not a relic: sudo

There is no `relics.hardening.sudo`, and the absence is deliberate. The two
settings usually asked for — `Defaults use_pty` and a dedicated sudo logfile —
are respectively already the upstream default (sudo ≥ 1.9.14, and always under
sudo-rs) and a worse deal than the journal sudo already writes to. The full
measurement and the escape hatch for a consumer who must satisfy the control
literally are in
[ANSSI-BP-028 fidelity](/stc/en/reference/anssi-bp-028/).

## Usage Example

Individual relics:

```nix
modules = [
  stc.nixosModules.relics-hardening-kernel
  stc.nixosModules.relics-hardening-network
  stc.nixosModules.relics-hardening-filesystem
  stc.nixosModules.relics-hardening-ssh
  stc.nixosModules.relics-hardening-modules
  stc.nixosModules.relics-hardening-scheduler
  stc.nixosModules.relics-hardening-audit
  stc.nixosModules.relics-hardening-firewall
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
  stc.relics.hardening.scheduler.enable = true;
  stc.relics.hardening.audit.enable = true;
  stc.relics.hardening.firewall.enable = true;

  # Ports stay yours to open (SSH is opened by services.openssh):
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
```

Gaming machine with hardening:

```nix
{
  stc.relics.hardening.kernel.enable = true;

  stc.relics.hardening.filesystem.enable = true;
  stc.relics.hardening.filesystem.gaming = true;  # allow exec in /tmp, /var/tmp and /dev/shm
  stc.relics.hardening.filesystem.shmSize = "4G"; # DXVK/VKD3D need more than 256M

  stc.relics.hardening.network.enable = true;
  stc.relics.hardening.ssh.enable = true;
}
```

## The cogitator-hardening Shortcut

For the common case of enabling all eight relics with defaults, use
[`cogitator-hardening`](/stc/en/cogitator/hardening/). One option instead of eight:

```nix
modules = [ stc.nixosModules.cogitator-hardening ];

# configuration.nix
{ stc.cogitator.hardening.enable = true; }
```

The cogitator does not prevent you from tuning individual options afterward —
`stc.relics.hardening.filesystem.tmpSize` and `stc.relics.hardening.ssh.allowedTCPForwarding`
remain configurable.

## Operational escapes added in v0.18.0

Four values these relics used to pin are now `lib.mkDefault`, because declining
them is operational rather than a change of threat model:

```nix
# Forward a remote GUI app, or hop through a bastion with your agent.
stc.relics.hardening.ssh = {
  allowedX11Forwarding = true;
  allowedAgentForwarding = true;
  allowedTunnel = true;
};

# Get core dumps back for one debugging session.
systemd.coredump.enable = true;
```

The three forwarding switches are **options**, not `mkDefault` values, and that
is deliberate. Written as `lib.mkDefault` they collided with upstream modules
setting the same thing — nixpkgs' slurm module writes
`services.openssh.settings.X11Forwarding = mkIf cfg.client.enable (mkDefault true)`,
and a hardened Slurm client stopped building. An option keeps the relic's value
deterministic against upstream and still leaves you one line.

:::danger[Re-enabling core dumps exposes secrets, and the PAM limit does not stop it]
An earlier version of this page said the relic's `security.pam.loginLimits`
entry keeps the hardening in place even with the handler back on. **That is
false, for two independent reasons:**

- `loginLimits` writes `/etc/security/limits.conf`, applied by `pam_limits` to
  PAM *login sessions*. A systemd service never went through it, so it never
  bounded a daemon's dumps.
- Enabling `systemd-coredump` installs a pipe `core_pattern`, and `core(5)` is
  explicit: *"The RLIMIT_CORE limit is not enforced for core dumps that are
  piped to a program"*. The limit then stops applying even to login sessions.

So with the handler on, every crashing daemon writes its **full address space** —
TLS private keys, session tokens, decrypted secrets — into
`/var/lib/systemd/coredump`. Enable it deliberately, for the crash you are
chasing, and turn it back off afterwards.
:::

What stays pinned is the relic's actual claim: `PasswordAuthentication = false`,
`KbdInteractiveAuthentication = false` and `PubkeyAuthentication = true`.
Demoting those would let a host documented as hardened quietly accept passwords
again, so contradicting them still stops your build. Full rule in
[Overridable defaults](/stc/en/reference/overridable-defaults/).
