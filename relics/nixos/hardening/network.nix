{
  config,
  lib,
  ...
}: let
  cfg = config.stc.relics.hardening.network;
  rpFilter =
    if cfg.strictReversePathFilter
    then 1
    else 2;
in {
  imports = [
    (lib.mkRenamedOptionModule ["stc" "hardening" "network" "enable"] ["stc" "relics" "hardening" "network" "enable"])
  ];

  options.stc.relics.hardening.network = {
    enable = lib.mkEnableOption "network sysctl hardening (spoofing, redirects, SYN flood)";

    strictReversePathFilter = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Reverse-path filtering mode (rp_filter). true = strict (1), the safe
        default for a single-homed host: packets arriving on an interface that
        would not be used to reach the source are dropped. Set to false = loose
        (2) for asymmetric routing, multi-homed hosts, or WireGuard/policy-routing
        setups where strict mode breaks legitimate return paths.
      '';
    };

    strictArp = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        ARP hardening (arp_ignore=1, arp_announce=2). Off by default: these
        restrict which addresses a host answers/announces ARP for and can break
        multi-homed hosts, Linux bridges, and container/Docker networking (which
        `../nixos` uses). Enable only on single-homed hosts where you have
        verified it does not disturb the network stack.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernel.sysctl =
      {
        # --- Spoofing / redirect protection (ANSSI-BP-028 R12) ---
        "net.ipv4.conf.all.rp_filter" = rpFilter;
        "net.ipv4.conf.default.rp_filter" = rpFilter;
        "net.ipv4.conf.all.accept_redirects" = 0;
        "net.ipv4.conf.default.accept_redirects" = 0;
        "net.ipv4.conf.all.secure_redirects" = 0;
        "net.ipv4.conf.default.secure_redirects" = 0;
        "net.ipv4.conf.all.send_redirects" = 0;
        "net.ipv4.conf.default.send_redirects" = 0;
        "net.ipv6.conf.all.accept_redirects" = 0;
        "net.ipv6.conf.default.accept_redirects" = 0;

        # --- Source routing rejection (ANSSI-BP-028 R12) ---
        # Source-routed packets let an attacker dictate the return path. Never
        # used on a normal host.
        "net.ipv4.conf.all.accept_source_route" = 0;
        "net.ipv4.conf.default.accept_source_route" = 0;
        "net.ipv6.conf.all.accept_source_route" = 0;
        "net.ipv6.conf.default.accept_source_route" = 0;

        # --- ICMP abuse prevention (ANSSI-BP-028 R12; echo_ignore_broadcasts is good practice beyond R12) ---
        "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
        "net.ipv4.icmp_ignore_bogus_error_responses" = 1;

        # --- SYN flood mitigation (ANSSI-BP-028 R12) ---
        "net.ipv4.tcp_syncookies" = 1;
        # Protect against TIME_WAIT assassination (ANSSI-BP-028 R12).
        "net.ipv4.tcp_rfc1337" = 1;

        # --- eBPF JIT hardening (ANSSI-BP-028 R12) ---
        # Harden the JIT against spraying attacks (constant blinding).
        "net.core.bpf_jit_harden" = 2;
      }
      // lib.optionalAttrs cfg.strictArp {
        # ARP hardening — opt-in, see strictArp option (ANSSI-BP-028 R12).
        "net.ipv4.conf.all.arp_ignore" = 1;
        "net.ipv4.conf.default.arp_ignore" = 1;
        "net.ipv4.conf.all.arp_announce" = 2;
        "net.ipv4.conf.default.arp_announce" = 2;
      };
  };
}
