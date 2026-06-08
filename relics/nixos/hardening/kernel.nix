# Relic: Kernel Hardening
# sysctl parameters that reduce the kernel attack surface.
# Recommended for any internet-facing machine. Non-negotiable for production.
{
  config,
  lib,
  ...
}: let
  cfg = config.stc.relics.hardening.kernel;
in {
  imports = [
    (lib.mkRenamedOptionModule ["stc" "hardening" "kernel" "enable"] ["stc" "relics" "hardening" "kernel" "enable"])
    (lib.mkRemovedOptionModule ["stc" "hardening" "kernel" "gaming"] "The gaming option has been removed. kernel.unprivileged_userns_clone is a Debian/Arch-hardened sysctl that has no effect on the vanilla NixOS kernel.")
    (lib.mkRemovedOptionModule ["stc" "relics" "hardening" "kernel" "gaming"] "The gaming option has been removed. kernel.unprivileged_userns_clone is a Debian/Arch-hardened sysctl that has no effect on the vanilla NixOS kernel.")
  ];

  options.stc.relics.hardening.kernel = {
    enable = lib.mkEnableOption "kernel sysctl hardening";
  };

  config = lib.mkIf cfg.enable {
    boot.kernel.sysctl = {
      # --- Memory layout ---
      "kernel.randomize_va_space" = 2; # Full ASLR
      "kernel.kptr_restrict" = 2; # Hide kernel pointers from all users
      "kernel.dmesg_restrict" = 1; # Restrict dmesg to root

      # --- Unprivileged capabilities ---
      "kernel.perf_event_paranoid" = 3; # Block perf for unprivileged users
      "kernel.unprivileged_bpf_disabled" = 1; # Block eBPF for unprivileged users
      # Restrict ptrace to direct children: a compromised process can no longer
      # attach to and read other processes of the same user (credential theft).
      # Pairs with perf_event_paranoid/bpf above. Note: a non-child gdb attach and
      # some debuggers/crash handlers need `sudo` or YAMA scope 0 to work.
      "kernel.yama.ptrace_scope" = 1;

      # --- kexec and SysRq ---
      # kexec allows replacing the running kernel — a significant attack vector.
      "kernel.kexec_load_disabled" = 1;
      "kernel.sysrq" = 0;

      # --- Core dumps ---
      # Core dumps can expose secrets and private keys. Disable entirely.
      "fs.suid_dumpable" = 0;

      # --- Filesystem hardening ---
      "fs.protected_hardlinks" = 1;
      "fs.protected_symlinks" = 1;
      "fs.protected_fifos" = 2;
      "fs.protected_regular" = 2;
    };

    # Disable systemd core dump handler — /bin/false doesn't exist on NixOS.
    systemd.coredump.enable = false;

    # Belt-and-suspenders: also disable core dumps via PAM resource limits.
    security.pam.loginLimits = [
      {
        domain = "*";
        item = "core";
        type = "hard";
        value = "0";
      }
    ];
  };
}
