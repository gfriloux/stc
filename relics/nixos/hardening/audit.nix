# Relic: Audit
# Runs auditd with a baseline ruleset loaded at boot — ANSSI-BP-028 R73.
#
# The categories are the usual baseline's: identity files, sudoers, privilege
# escalation through a setuid execve, kernel module load/unload, mounts. Login
# and logout need no rule: libpam itself (nixpkgs builds it with audit support)
# emits USER_AUTH, USER_START and USER_END for every PAM stack.
#
# No watch sits outside /etc, and that is the constraint to keep when adding
# rules. Upstream loads the whole file with one `auditctl -R` from
# audit-rules-nixos.service, before sysinit.target: a single line that fails
# aborts the load, the unit's ExecStopPost turns auditing off, and auditd still
# reports active. A watch on /var/log/wtmp does exactly that — /var/log does not
# exist yet at that point, and on an impermanence host it is a bind mount set up
# later anyway. Login records come from PAM instead.
#
# Mounts are filtered on auid!=unset: unfiltered, systemd unmounting
# /run/credentials/<unit> on every unit start floods the log. Mounts from a
# login session (sudo included) keep the admin's auid and stay recorded.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.stc.relics.hardening.audit;

  # The b32 syscall table is the classic bypass of a b64-only rule on x86_64;
  # other platforms get the b64 rules alone (aarch64's arm32 compat table stays
  # uncovered). execveat too: fexecve() goes through it.
  syscallRules = arch: mountCalls: [
    "-a always,exit -F arch=${arch} -C euid!=uid -F auid!=unset -S execve,execveat -k user_emulation"
    "-a always,exit -F arch=${arch} -S init_module,finit_module,delete_module -k kernel_modules"
    "-a always,exit -F arch=${arch} -F auid!=unset -S ${mountCalls} -k mounts"
  ];
in {
  options.stc.relics.hardening.audit = {
    enable = lib.mkEnableOption "auditd with STC's baseline audit ruleset (identity, sudoers, setuid execve, kernel modules, mounts)";

    immutable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Lock the audit configuration until the next reboot (`auditctl -e 2`,
        `security.audit.enable = "lock"`). Root can then neither remove nor
        change the rules: a nixos-rebuild switch that touches them fails the
        audit-rules-nixos unit until the machine reboots.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # auditctl rejects arch=b64 on a 32-bit host, and one rejected line aborts
    # the whole load.
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.is64bit;
        message = "stc.relics.hardening.audit: the baseline rules are written for 64-bit hosts; on a 32-bit one auditctl rejects them and loads no rule at all.";
      }
    ];

    security.auditd.enable = true;
    # Plain value: beats the mkDefault true upstream auditd sets.
    security.audit.enable =
      if cfg.immutable
      then "lock"
      else true;
    # Upstream defaults to 1024; the usual baselines ask for at least 8192 so
    # the events emitted before auditd starts are not lost.
    security.audit.backlogLimit = lib.mkDefault 8192;

    # NixOS writes an auditd.conf with no rotation settings, and auditd's
    # built-in defaults are num_logs 0 and max_log_file_action IGNORE:
    # audit.log would grow until the disk is full. 5 files of 8 MiB (the
    # values of auditd's own example configuration) cap it at 40 MiB.
    security.auditd.settings = {
      max_log_file = lib.mkDefault 8;
      num_logs = lib.mkDefault 5;
      max_log_file_action = lib.mkDefault "rotate";
    };

    security.audit.rules =
      [
        "-w /etc/passwd -p wa -k identity"
        "-w /etc/group -p wa -k identity"
        "-w /etc/shadow -p wa -k identity"
        # Absent on NixOS; the watch loads anyway and catches its creation.
        "-w /etc/gshadow -p wa -k identity"
        "-w /etc/sudoers -p wa -k scope"
        "-w /etc/sudoers.d -p wa -k scope"
      ]
      ++ syscallRules "b64" "mount,umount2"
      ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 (syscallRules "b32" "mount,umount,umount2");
  };
}
