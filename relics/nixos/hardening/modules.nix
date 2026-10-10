# Relic: Kernel Module Blacklist
# Blacklists high-risk and unused kernel modules to shrink the attack surface.
#
# Three families are disabled by default:
#   - FireWire (firewire-*): a classic DMA attack vector — a hostile device can
#     read/write physical memory over the bus.
#   - Rare/legacy network protocols (dccp, sctp, rds, tipc): almost never used on
#     a normal host, yet a recurring source of kernel CVEs.
#   - Legacy filesystems (cramfs, freevxfs, jffs2, hfs, hfsplus): drivers nothing
#     on a normal host mounts, each one a parser reachable from removable media.
#
# `udf` and `usb-storage` are deliberately NOT in the defaults, even though the
# usual baselines list them: both still have legitimate uses (optical media, USB
# installers) and `blacklistedKernelModules` is a list — extraBlacklist can add
# to it but nothing subtracts, so a bad default has no clean escape hatch. Hosts
# that want them gone put them in extraBlacklist.
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
    enable = lib.mkEnableOption "blacklist of high-risk / unused kernel modules (DMA, rare network protocols, legacy filesystems)";

    extraBlacklist = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["bluetooth" "uvcvideo" "udf" "usb-storage"];
      description = ''
        Additional kernel modules to blacklist, merged with the curated defaults.
        Use this for host-specific attack-surface reduction (unused wireless
        stacks, webcams, etc.) without forking the relic. `udf` (optical media)
        and `usb-storage` belong here rather than in the defaults: both are still
        legitimately used, so the choice is left to the host.
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
        # Legacy filesystems, no longer mounted on a normal host — ANSSI-BP-028 R10
        "cramfs" # compressed read-only initrd format, superseded by squashfs
        "freevxfs" # Veritas, never present on a Linux host
        "jffs2" # embedded flash
        "hfs" # classic Mac OS
        "hfsplus" # macOS, only useful on a dual-boot machine
      ]
      ++ cfg.extraBlacklist;
  };
}
