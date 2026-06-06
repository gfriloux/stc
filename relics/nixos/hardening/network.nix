{ config, lib, ... }:

let
  cfg = config.stc.relics.hardening.network;
in
{
  imports = [
    (lib.mkRenamedOptionModule [ "stc" "hardening" "network" "enable" ] [ "stc" "relics" "hardening" "network" "enable" ])
  ];

  options.stc.relics.hardening.network = {
    enable = lib.mkEnableOption "network sysctl hardening (spoofing, redirects, SYN flood)";
  };

  config = lib.mkIf cfg.enable {
    boot.kernel.sysctl = {
      # --- Spoofing / redirect protection ---
      "net.ipv4.conf.all.rp_filter" = 1;
      "net.ipv4.conf.default.rp_filter" = 1;
      "net.ipv4.conf.all.accept_redirects" = 0;
      "net.ipv4.conf.default.accept_redirects" = 0;
      "net.ipv4.conf.all.secure_redirects" = 0;
      "net.ipv4.conf.default.secure_redirects" = 0;
      "net.ipv4.conf.all.send_redirects" = 0;
      "net.ipv4.conf.default.send_redirects" = 0;
      "net.ipv6.conf.all.accept_redirects" = 0;
      "net.ipv6.conf.default.accept_redirects" = 0;

      # --- ICMP abuse prevention ---
      "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
      "net.ipv4.icmp_ignore_bogus_error_responses" = 1;

      # --- SYN flood mitigation ---
      "net.ipv4.tcp_syncookies" = 1;
    };
  };
}
