{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.stc.relics.zfs;

  zfsCompatibleKernelPackages =
    lib.filterAttrs (
      name: kernelPackages:
        (builtins.match "linux_[0-9]+_[0-9]+" name)
        != null
        && (builtins.tryEval kernelPackages).success
        && (!kernelPackages.${config.boot.zfs.package.kernelModuleAttribute}.meta.broken)
    )
    pkgs.linuxKernel.packages;

  latestKernelPackage = lib.last (
    lib.sort (a: b: (lib.versionOlder a.kernel.version b.kernel.version)) (
      builtins.attrValues zfsCompatibleKernelPackages
    )
  );
in {
  imports = [
    (lib.mkRenamedOptionModule ["stc" "zfs" "enable"] ["stc" "relics" "zfs" "enable"])
    (lib.mkRenamedOptionModule ["stc" "zfs" "scrubInterval"] ["stc" "relics" "zfs" "scrubInterval"])
    (lib.mkRenamedOptionModule ["stc" "zfs" "autoSnapshot" "enable"] ["stc" "relics" "zfs" "autoSnapshot" "enable"])
    (lib.mkRenamedOptionModule ["stc" "zfs" "autoSnapshot" "daily"] ["stc" "relics" "zfs" "autoSnapshot" "daily"])
    (lib.mkRenamedOptionModule ["stc" "zfs" "autoSnapshot" "poolName"] ["stc" "relics" "zfs" "autoSnapshot" "poolName"])
  ];

  options.stc.relics.zfs = {
    enable = lib.mkEnableOption "ZFS kernel, boot support, and pool maintenance (scrub, TRIM, ZED)";

    scrubInterval = lib.mkOption {
      type = lib.types.str;
      default = "monthly";
      description = "systemd calendar expression for auto-scrub. Monthly is sufficient for most workloads.";
    };

    autoSnapshot = {
      enable = lib.mkEnableOption "periodic ZFS snapshots on the persist dataset";

      daily = lib.mkOption {
        type = lib.types.int;
        default = 7;
        description = "Number of daily snapshots to keep.";
      };

      poolName = lib.mkOption {
        type = lib.types.str;
        description = "ZFS pool name. Snapshots are enabled on <poolName>/persist and disabled on the root pool to avoid snapshotting ephemeral datasets.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    boot = {
      kernelPackages = latestKernelPackage;

      supportedFilesystems = ["zfs"];
      initrd.supportedFilesystems = ["zfs"];

      # Force-import the root pool so the system boots even when the pool
      # was last used on a different host (e.g. after nixos-anywhere install).
      # forceImportAll stays false to protect non-root pools.
      zfs = {
        forceImportRoot = true;
        forceImportAll = false;
      };
    };

    services.zfs = {
      autoScrub = {
        enable = true;
        interval = cfg.scrubInterval;
      };

      # TRIM support for SSDs and thin-provisioned virtual disks.
      trim.enable = true;

      # ZFS Event Daemon — monitors pool health, logs errors.
      zed.settings = {
        # Not /tmp: world-readable tmpfs. /var/log keeps it root-owned and persistent.
        ZED_DEBUG_LOG = "/var/log/zed.debug.log";
        ZED_NOTIFY_VERBOSE = 0;
      };

      autoSnapshot = lib.mkIf cfg.autoSnapshot.enable {
        enable = true;
        daily = cfg.autoSnapshot.daily;
      };
    };

    # Disable auto-snapshot on the pool root (ephemeral datasets) and enable
    # it only on /persist. Runs at every activation but is idempotent.
    system.activationScripts.zfsAutoSnapshot = lib.mkIf cfg.autoSnapshot.enable ''
      ${pkgs.zfs}/bin/zfs set com.sun:auto-snapshot=false ${cfg.autoSnapshot.poolName} || true
      ${pkgs.zfs}/bin/zfs set com.sun:auto-snapshot=true ${cfg.autoSnapshot.poolName}/persist || true
    '';
  };
}
