# Ledger — plan: .claude/plans/v0.22.0/audit.md

Pre-flight: issue #31 read; upstream `nixos/modules/security/{audit,auditd}.nix`
and `nixos/tests/audit.nix` read on the locked nixpkgs; two spike nixosTests
(`cogitator-hardening` + candidate rules) — results in the plan's measured
premises. Consumer `gfriloux/nixos`: no host imports `cogitator-hardening`,
`dreadnought` or a sarcophagus profile.

Pre-flight: step 3 consumes `stc.relics.hardening.audit.enable` as step 2
produces it, through `stc.cogitator.hardening.enable` already set by the
proving nodes.

Step 1: Ruling: **CIS wtmp/btmp/lastlog/faillock watches dropped.** Under
`/var`, they abort the whole rule file at sysinit (spike 1) and PAM already
emits the login records (spike 2). Cost if wrong: a record CIS scanners look
for by key, not by content.

Step 1: Ruling: **mount rule filtered on `auid!=unset`** (CIS form, not
ANSSI's unfiltered one): unfiltered, systemd's per-unit credential unmounts
flood the log. Admin mounts from a session keep their auid and stay recorded.

Step 1: Ruling: **journald duplication left alone.** Masking
`systemd-journald-audit.socket` is the consumer's call; documented.

Step 1: Ruling: **time-change rules not in the baseline.** `adjtimex` is called
continuously by timesyncd/chrony; out of the issue's six categories.

Step 1: plan approved by the user: audit in `cogitator-hardening` at
mkDefault — yes; `immutable` off by default — yes (the switch failure until
reboot was the deciding cost).

Step 2: `relics/nixos/hardening/audit.nix`, registered as
`relics-hardening-audit`, wired into `cogitator-hardening` at mkDefault.
Measured by `nix-instantiate --eval` on a minimal nixosSystem with the suite:
default → `security.audit.enable = true`, 12 rules (x86_64: 6 watches + 3 b64
+ 3 b32), backlog 8192, cmdline `audit=1 audit_backlog_limit=8192`, no failed
assertion; `immutable = true` → `"lock"`; relic off → audit off, 0 rules,
backlog 1024; consumer `backlogLimit = 2048` wins, a plain consumer rule lands
after the baseline, a `lib.mkBefore` one first (what `-a never` exclusions
need). Seal: hardening cogitator 6 → 7, `count` row for the relic, `watch`
row for `security.audit.backlogLimit`; `just ci` green (26 files, 52 options).

Step 3: ANSSI text read in the v2.0 guide itself (fr_np_linux_configuration-v2.0.pdf,
pdftotext): R73 "Journaliser l'activité système avec auditd", levels M/I/R
(minimal); R33 "Assurer l'imputabilité des actions d'administration" (M/I),
whose strongest form logs every execve. Third-party catalogues map auditd to
R33 only; both rows go in the matrix, the R73 example ruleset compared line by
line.

Step 3: provings. Three red runs, none a relic bug:
- `auditctl -l` prints watches as `-k <key>` and syscall rules as
  `-F key=<key>`; the key assertion only knew the second form (the rule
  count, checked first, was already right). Fixed in both provings.
- the setuid execve from SSH never reached sshd: `Connection reset`. The
  authorized-keys subtest's deliberate refused login earns 127.0.0.1 the ssh
  relic's `authfail:3600` PerSourcePenalty. Audit subtests moved before it,
  `ssh` command hoisted to the top of the script.
- a plain `mount` from an unprivileged user is refused by util-linux before
  any syscall, so nothing to record. The mount now runs under `unshare -rm`
  (tmpfs is mountable in a user namespace; the auid is unchanged).
Green: `hardening` (rules loaded, `enabled 1`, `backlog_limit 8192`, rule
count equal to `security.audit.rules`, five keys; events identity,
kernel_modules `name=dummy`, user_emulation `comm=sudo` with auid declared,
mounts with auid declared, PAM USER_START acct=declared) and `sarcophagus-kvm`
(rules loaded on both boots; a boot-1 identity record read back on boot 2 from
the persisted /var/log).

Step 4: docs EN + FR — relics/hardening (Audit section: options, key table,
the one-bad-rule danger box, appending rules and mkBefore, logs and journald,
immutable; counts six → seven), relics/index row, cogitator/hardening,
overridable-defaults row, anssi-bp-028 (R33 + R73 in the rule table, an
audit section comparing the guide's example), provings/index rows. Parity OK.

Gates: `just ci` green (26 files, 52 options); local-vm, aws-ami, dreadnought
drvPath OK; consumer RogueLeader, clochette, exampleHost, skitarii and
`kuri@exampleHost` evaluate, `security.audit.enable = false` on all four hosts.

Closing review (fresh context): no Critical. Dreadnought proving built by the
reviewer: green, `audit=1 audit_backlog_limit=8192` on its cmdline.
- I1 taken: "rotated by auditd itself" was false. The rendered auditd.conf has
  only space_left/admin_space_left/plugin_dir, and auditd's clear_config()
  defaults num_logs 0, max_log_size_action IGNORE. Ruling: the relic sets
  max_log_file 8, num_logs 5, max_log_file_action rotate at mkDefault (auditd's
  own example values, 40 MiB cap); seal count 1 → 4, three watch rows; the
  proving asserts the three lines in /etc/audit/auditd.conf. Docs corrected.
- M1 example `-F uid=backup` → numeric uid, with why (a name resolved at load,
  unknown → whole load aborted).
- M2 login records attributed to libpam, not pam_unix (code comment, docs).
- M3 "enabled 1 (2 with immutable)". M4 journald: declarative
  `systemd.sockets.systemd-journald-audit.enable = false`.
- M5 `execveat` added to user_emulation (in the x86_64, i386 and aarch64
  tables; R33 itself cites execve,execveat).
- M6 auid filter justified per rule. M7 assertion `hostPlatform.is64bit`.
- M8 proving uses `-ul` (auid only) instead of `-ua`.
- M9 overridable-defaults row; stale hardening descriptions fixed in
  cogitator index, dreadnought/sarcophagus pages (now naming auditd), README,
  cogitator/default.nix, architecture (EN + FR).
- M10 doc: use `immutable`, not `security.audit.enable = "lock"` (conflict).

Gates after review fixes: provings `hardening` and `sarcophagus-kvm` green;
`just ci` green (26 files, 55 options).
