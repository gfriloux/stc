{
  config,
  lib,
  ...
}: let
  cfg = config.stc.relics.hardening.network;
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
  };

  config = lib.mkIf cfg.enable {
    boot.kernel.sysctl = let
      rpFilter =
        if cfg.strictReversePathFilter
        then 1
        else 2;
    in {
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

      # --- ICMP abuse prevention (ANSSI-BP-028 R12; echo_ignore_broadcasts is good practice beyond R12) ---
      "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
      "net.ipv4.icmp_ignore_bogus_error_responses" = 1;

      # --- SYN flood mitigation (ANSSI-BP-028 R12) ---
      "net.ipv4.tcp_syncookies" = 1;
    };
  };
}
