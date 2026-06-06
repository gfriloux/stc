# Relic: Base Networking
# Sensible networking defaults. DHCP on all interfaces, Quad9 DNS.
#
# Quad9 (9.9.9.9) was chosen as default: privacy-respecting, no query logging,
# malware-blocking, DNSSEC-validating. Change if your threat model differs.
{ config, lib, ... }:

let
  cfg = config.stc.relics.networking;
in
{
  imports = [
    (lib.mkRenamedOptionModule [ "stc" "networking" "enable" ] [ "stc" "relics" "networking" "enable" ])
    (lib.mkRenamedOptionModule [ "stc" "networking" "domain" ] [ "stc" "relics" "networking" "domain" ])
    (lib.mkRenamedOptionModule [ "stc" "networking" "nameservers" ] [ "stc" "relics" "networking" "nameservers" ])
  ];

  options.stc.relics.networking = {
    enable = lib.mkEnableOption "base networking configuration";

    domain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "DNS search domain. Null means no domain is set.";
    };

    nameservers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "9.9.9.9" "149.112.112.112" ];
      description = "DNS resolvers. Defaults to Quad9 (privacy-respecting, DNSSEC, no logging).";
    };
  };

  config = lib.mkIf cfg.enable {
    networking = {
      domain = lib.mkIf (cfg.domain != null) cfg.domain;
      inherit (cfg) nameservers;
      usePredictableInterfaceNames = lib.mkDefault true;
      # DHCP on all interfaces. Override per-interface in your system config.
      useDHCP = lib.mkDefault true;
    };
  };
}
