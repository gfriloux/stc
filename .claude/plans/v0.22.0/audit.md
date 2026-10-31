## Feature Plan: auditd relic with a baseline ruleset (#31)

**Type:** Architectural — new relic

**Goal:** `stc.relics.hardening.audit.enable = true` runs auditd with a curated
baseline ruleset loaded at boot, and `cogitator-hardening` turns it on.

**Why:** the hardening relics cover sysctl, mounts, modules, SSH and cron, but
nothing records who changed an identity file, loaded a module or ran a setuid
program. `security.audit` / `security.auditd` appear nowhere in the repository
(#31). ANSSI-BP-028 R73 (journaliser l'activité système avec auditd) is the
referential; the issue's CIS 4.1.x list is the checklist of categories.

**Architecture:** a thin relic over the upstream `security.audit` (kernel side,
rules) and `security.auditd` (daemon) modules: STC adds the ruleset and two
defaults, never re-wraps upstream options. Rules land in `security.audit.rules`,
so a consumer appends their own there directly.

### Measured premises (2026-10-31, two spike nixosTests on the locked nixpkgs)

- Upstream loads rules from `audit-rules-nixos.service`: `DefaultDependencies =
  false`, before `sysinit.target`, `auditctl -R` on a single file. **One rule
  that fails to load aborts the whole file**; `ExecStopPost` then runs
  `auditctl -e 0` and `-D`. Spike 1: `-w /var/log/lastlog -p wa` failed
  (`/var/log` does not exist that early) → `No rules`, `enabled 0`, while
  `auditd.service` reported **active**. The only visible trace is the failed
  `audit-rules-nixos` unit.
- So no watch may sit under `/var` (or any path not on the root filesystem at
  sysinit). On an impermanence host `/var/log` is a bind mount set up later:
  a watch would hang on the directory underneath it.
- Watches under `/etc` load even when the file is absent (`/etc/gshadow`,
  `/etc/sudoers.d` do not exist on NixOS; both loaded) and fire on a real
  change (`chmod 644 /etc/passwd` → event `key=identity`).
- Login/logout is recorded natively: NixOS `pam_unix` links `libaudit`, and a
  `su` produced `USER_AUTH`, `CRED_ACQ`, `USER_START`, `USER_END`. The CIS
  `wtmp`/`btmp`/`lastlog` watches are redundant and, per the first point,
  unsafe. Dropped.
- Module loads: `-S init_module,finit_module,delete_module` caught udev's,
  `modprobe net-pf-17`'s and a manual `modprobe dummy` (`KERN_MODULE name=dummy`).
- Mounts without an `auid` filter catch systemd unmounting
  `/run/credentials/<unit>` on every unit start — constant noise. With
  `-F auid!=unset` only mounts from a login session remain.
- `-C euid!=uid -F auid!=unset -S execve` produced nothing from the test
  driver's root shell or from `su` run by it: both have `auid=unset`. Proving
  it needs a real login session (SSH), which `provings/hardening.nix` already
  has.
- journald also receives every audit record (`_TRANSPORT=audit`: 3065 journal
  lines for 3476 in `audit.log` after boot). Duplication, not loss.
- Kernel command line gains `audit=1 audit_backlog_limit=<n>` (upstream).

### User decisions (2026-10-31, plan approved)

- In `cogitator-hardening` at `mkDefault`, like the six others (the issue asks
  for it). Reaches `dreadnought`, `sarcophagus-kvm`, `sarcophagus-aws`, which
  enable the suite. No `gfriloux/nixos` host imports any of them.
- `immutable` (rules locked until reboot, `-e 2`) off by default: with it, a
  `nixos-rebuild switch` that changes rules fails the unit until reboot.

### Options

```nix
stc.relics.hardening.audit = {
  enable = lib.mkEnableOption "auditd with STC's baseline audit ruleset";
  immutable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Lock the audit configuration until the next reboot (auditctl -e 2,
      security.audit.enable = "lock"). Rules can then be neither removed nor
      changed by root: a nixos-rebuild switch that touches them fails the
      audit-rules-nixos unit until reboot.
    '';
  };
};
```

Config under `lib.mkIf cfg.enable`:

- `security.auditd.enable = true;`
- `security.audit.enable = if cfg.immutable then "lock" else true;` (plain:
  beats upstream auditd's own `mkDefault true`)
- `security.audit.backlogLimit = lib.mkDefault 8192;` (CIS asks ≥ 8192;
  upstream 1024; watch row in the seal)
- `security.audit.rules` = the baseline below, `b32` lines only when
  `pkgs.stdenv.hostPlatform.isx86_64`.

Baseline (keys are what `ausearch -k` takes):

```
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/sudoers -p wa -k scope
-w /etc/sudoers.d -p wa -k scope
-a always,exit -F arch=b64 -C euid!=uid -F auid!=unset -S execve -k user_emulation
-a always,exit -F arch=b64 -S init_module,finit_module,delete_module -k kernel_modules
-a always,exit -F arch=b64 -F auid!=unset -S mount,umount2 -k mounts
# x86_64 only: the same three syscall rules with arch=b32 (b32 mounts: mount,umount,umount2)
```

### Global Constraints

- Canonical namespace `stc.relics.hardening.audit.*`; module `relics-hardening-audit`.
- No watch outside `/etc` in the baseline (measured: one bad line disables all
  auditing).
- Rules stay in `security.audit.rules`; no `extraRules` wrapper.
- Schematics local-vm, aws-ami, dreadnought keep evaluating.
- Every new `mkDefault` gets its seal row.

### Review Focus

- A consumer rule on a `/var` path silently disables all auditing — the doc
  must say it and name the failed unit to look for.
- The proving asserts `enabled 1` **and** `audit-rules-nixos` active, not just
  `auditd` active (the spike-1 trap).
- `immutable` + switch behaviour described accurately.
- Disk: `/var/log/audit` under auditd's own rotation (upstream defaults);
  persisted on impermanence hosts since `/var/log` is.

### Affected Files

- `relics/nixos/hardening/audit.nix` (new), `relics/default.nix`
- `cogitator/nixos/hardening.nix`
- `scripts/option-priorities.tsv`
- `provings/hardening.nix`, `provings/sarcophagus-kvm.nix`
- docs EN + FR: `relics/hardening.md`, `relics/index.md`,
  `cogitator/hardening.md`, `reference/anssi-bp-028.md`, `provings/index.md`,
  `reference/overridable-defaults.md` if it lists the suite's relics

### Atomic Steps

#### Step 1: plan + ledger
#### Step 2: the relic, registered, wired into `cogitator-hardening` (mkDefault), seal rows

Interfaces — produces `stc.relics.hardening.audit.enable` (bool, false) and
`.immutable` (bool, false). Verification: `nix-instantiate --eval` of
`security.audit.rules` length and `security.audit.enable` on local-vm with the
relic on / off / immutable; `just ci`.

Commit: `feat(relics-hardening-audit): auditd with a boot-safe baseline ruleset (#31)`

#### Step 3: provings

Consumes `stc.relics.hardening.audit.enable` through `cogitator-hardening`.
`provings/hardening.nix`: `audit-rules-nixos` and `auditd` active; `auditctl
-s` has `enabled 1` and `backlog_limit 8192`; `auditctl -l` carries the four
syscall keys and the identity/scope watches; events: `chmod` on
`/etc/passwd` → `identity`, `modprobe dummy` → `kernel_modules`, SSH login as
`declared` then `sudo -n true` → `user_emulation` and a `USER_LOGIN`/`USER_START`
record, `mount -t tmpfs` from that session → `mounts`.
`provings/sarcophagus-kvm.nix`: on both boots, `audit-rules-nixos` active and
`enabled 1` (rules load on a real impermanence layout).

Commit: `test(provings): auditd rules load at boot and record the baseline events (#31)`

#### Step 4: docs EN + FR

`relics/hardening.md` section (options, baseline table with keys, the
`/var` trap, appending rules and `mkBefore` for `-a never` exclusions,
journald duplication, `immutable`); relics index row; cogitator page (seven
relics); ANSSI matrix R73 row + section; provings index.

Commit: `docs: auditd relic, baseline keys and R73 row (en, fr) (#31)`

### Quality Gates

- `just ci` green (seal included).
- Provings `hardening` and `sarcophagus-kvm` green.
- `nix eval` of the three schematics' `drvPath`.
- Consumer `gfriloux/nixos`: four hosts evaluate with `--override-input`.
- One fresh-context review at branch close.
