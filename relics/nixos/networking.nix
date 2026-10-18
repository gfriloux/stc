# Relic: Base Networking
# Sensible networking defaults. DHCP on all interfaces, Quad9 DNS.
#
# Quad9 (9.9.9.9) was chosen as default: privacy-respecting, no query logging,
# malware-blocking, DNSSEC-validating. Change if your threat model differs.
{
  config,
  lib,
  ...
}: let
  cfg = config.stc.relics.networking;
in {
  imports = [
    (lib.mkRenamedOptionModule ["stc" "networking" "enable"] ["stc" "relics" "networking" "enable"])
    (lib.mkRenamedOptionModule ["stc" "networking" "domain"] ["stc" "relics" "networking" "domain"])
    (lib.mkRenamedOptionModule ["stc" "networking" "nameservers"] ["stc" "relics" "networking" "nameservers"])
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
      default = ["9.9.9.9" "149.112.112.112"];
      description = "DNS resolvers. Defaults to Quad9 (privacy-respecting, DNSSEC, no logging).";
    };

    dhcp = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Use DHCP on all interfaces.

        An option rather than a `lib.mkDefault` on `networking.useDHCP`, and the
        reason is a measured collision: upstream modules write that option with
        `mkDefault` too — `services/networking/ifstate.nix` writes `false`,
        `virtualisation/vz-vm.nix` and the facter hardware module write `true` —
        and two disagreeing `mkDefault`s are a build error. Measured: this relic
        together with `services.ifstate.enable = true` did not evaluate at all.

        Set this to `false` and declare your interfaces yourself, or leave it on.
        Either way the relic's value is deterministic against whatever upstream
        defaults next release.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    networking = {
      domain = lib.mkIf (cfg.domain != null) cfg.domain;
      inherit (cfg) nameservers;
      usePredictableInterfaceNames = lib.mkDefault true;
      # From the option, at normal priority — see stc.relics.networking.dhcp for
      # the collision that rules out mkDefault here.
      useDHCP = cfg.dhcp;
    };
  };
}
