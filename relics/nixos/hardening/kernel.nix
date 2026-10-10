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
      # --- Memory layout (ANSSI-BP-028 R9) ---
      "kernel.randomize_va_space" = 2; # Full ASLR
      "kernel.kptr_restrict" = 2; # Hide kernel pointers from all users
      "kernel.dmesg_restrict" = 1; # Restrict dmesg to root

      # --- Unprivileged capabilities (ANSSI-BP-028 R9) ---
      "kernel.perf_event_paranoid" = 3; # Block perf for unprivileged users
      "kernel.unprivileged_bpf_disabled" = 1; # Block eBPF for unprivileged users
      # Restrict ptrace to direct children: a compromised process can no longer
      # attach to and read other processes of the same user (credential theft).
      # Pairs with perf_event_paranoid/bpf above. Note: a non-child gdb attach and
      # some debuggers/crash handlers need `sudo` or YAMA scope 0 to work.
      "kernel.yama.ptrace_scope" = 1; # ANSSI-BP-028 R11 (Yama LSM)

      # --- kexec and SysRq ---
      # kexec allows replacing the running kernel — a significant attack vector.
      # ANSSI-BP-028 disables kexec at compile time (CONFIG_KEXEC unset); we take
      # the runtime equivalent, which suits a vanilla nixpkgs kernel.
      "kernel.kexec_load_disabled" = 1;
      "kernel.sysrq" = 0; # ANSSI-BP-028 R9

      # --- Fail closed on a kernel fault (ANSSI-BP-028 R9) ---
      # An oops ("Oops:" / "BUG:" in dmesg) is a real fault: by default the
      # kernel kills the faulting task and limps on in a doubtful state. Several
      # exploitation techniques tolerate — or deliberately provoke — a stream of
      # oopses (KASLR brute-force, heap spraying), so every survived oops is a
      # free retry for the attacker. Panic instead.
      # Not to be confused with kernel.panic_on_warn, which fires on WARN_ON()
      # ("WARNING: ... at <file>:<line>") — a developer assertion, not a fault.
      # ANSSI does not ask for it and STC does not set it: a benign driver quirk
      # (a DRM framebuffer teardown, say) would take the machine down.
      "kernel.panic_on_oops" = 1;
      # panic_on_oops=1 on its own *freezes* the machine, because kernel.panic
      # defaults to 0 (wait forever). A headless node would then need console
      # access to come back, so bound the stop and reboot. This is not part of
      # R9 — it is the availability half of the trade, and the reason
      # panic_on_oops is safe to turn on by default here. Prefer a frozen
      # machine for post-mortem? `boot.kernel.sysctl."kernel.panic" = mkForce 0`.
      "kernel.panic" = 30;

      # --- R9 settings deliberately left at their defaults ---
      # kernel.pid_max: R9 asks for 65536, which *raises* the historical kernel
      # default of 32768 — a wider PID space recycles PIDs more slowly. systemd
      # ships sysctl.d/50-pid-max.conf with 4194304, so a NixOS host already
      # exceeds R9 by a factor of 64 and writing 65536 would be a regression.
      # provings/hardening.nix asserts it as a floor.
      # kernel.perf_cpu_time_max_percent / kernel.perf_event_max_sample_rate:
      # R9 asks for 1 on both. perf_event_paranoid=3 above already denies perf
      # to unprivileged users, so these only throttle root's own profiling —
      # and the kernel self-tunes the sample rate when the NMI handler gets
      # expensive ("perf: interrupt took too long ... lowering ... to 40000").
      # Evaluated, not adopted — see docs reference/anssi-bp-028.md.

      # --- Core dumps (ANSSI-BP-028 R14) ---
      # Core dumps can expose secrets and private keys. Disable entirely.
      "fs.suid_dumpable" = 0;

      # --- Filesystem hardening (ANSSI-BP-028 R14) ---
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
