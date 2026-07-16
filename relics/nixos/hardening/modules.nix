# Relic: Kernel Module Blacklist
# Blacklists high-risk and unused kernel modules to shrink the attack surface.
#
# Two families are disabled by default:
#   - FireWire (firewire-*): a classic DMA attack vector — a hostile device can
#     read/write physical memory over the bus.
#   - Rare/legacy network protocols (dccp, sctp, rds, tipc): almost never used on
#     a normal host, yet a recurring source of kernel CVEs.
#
# This is the *soft* form of ANSSI-BP-028 R10 (disable unused modules): a targeted
# blacklist rather than the full `kernel.modules_disabled=1` lockdown, which would
# break on-demand module loading and needs case-by-case evaluation.
{
  config,
  lib,
  ...
}: let
  cfg = config.stc.relics.hardening.modules;
in {
  options.stc.relics.hardening.modules = {
    enable = lib.mkEnableOption "blacklist of high-risk / unused kernel modules (DMA + rare network protocols)";

    extraBlacklist = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["bluetooth" "uvcvideo"];
      description = ''
        Additional kernel modules to blacklist, merged with the curated defaults.
        Use this for host-specific attack-surface reduction (unused wireless
        stacks, webcams, etc.) without forking the relic.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    boot.blacklistedKernelModules =
      [
        # DMA attack vector (FireWire) — ANSSI-BP-028 R10
        "firewire-core"
        "firewire-ohci"
        "firewire-sbp2"
        # Rare/legacy network protocols, frequent CVE vectors — ANSSI-BP-028 R10
        "dccp"
        "sctp"
        "rds"
        "tipc"
      ]
      ++ cfg.extraBlacklist;
  };
}
