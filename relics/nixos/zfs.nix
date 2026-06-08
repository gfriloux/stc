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

  # Known LTS kernel series, newest first. ZFS supports LTS releases longest;
  # non-LTS kernels often reach EOL before ZFS supports the next one (see the
  # nixpkgs zfs.latestCompatibleLinuxPackages deprecation note). Add a newer
  # series here when it lands.
  ltsKernelSeries = ["linux_6_12" "linux_6_6" "linux_6_1" "linux_5_15"];

  ltsKernelPackage = let
    available = builtins.filter (n: zfsCompatibleKernelPackages ? ${n}) ltsKernelSeries;
  in
    if available == []
    then throw "stc.relics.zfs: no ZFS-compatible LTS kernel found among ${toString ltsKernelSeries}; set stc.relics.zfs.kernel = \"latest\" or update ltsKernelSeries."
    else zfsCompatibleKernelPackages.${builtins.head available};

  selectedKernelPackage =
    if cfg.kernel == "lts"
    then ltsKernelPackage
    else latestKernelPackage;
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

    kernel = lib.mkOption {
      type = lib.types.enum ["lts" "latest"];
      default = "lts";
      description = ''
        Which ZFS-compatible kernel to track.
        - "lts" (default): newest ZFS-compatible long-term-support kernel — stable,
          minimal churn, the right choice for production/servers.
        - "latest": newest ZFS-compatible kernel — follows nixpkgs closely, more churn.

        ZFS supports LTS kernels longest; non-LTS releases often reach EOL before
        ZFS supports the next one, which can force manual intervention.
      '';
    };

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
      kernelPackages = selectedKernelPackage;

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
    # it only on /persist. Runs at every activation but is idempotent: `zfs set`
    # to the same value is a no-op that exits 0, so re-running on later boots is
    # harmless. We guard on dataset existence rather than masking every error with
    # `|| true` — that would also swallow a genuinely broken pool (the pattern PR
    # round 2 removed elsewhere). A missing dataset is skipped with a warning;
    # any other `zfs set` failure on an existing dataset aborts activation loudly.
    system.activationScripts.zfsAutoSnapshot = lib.mkIf cfg.autoSnapshot.enable (
      let
        zfs = "${pkgs.zfs}/bin/zfs";
        setSnapshot = ds: val: ''
          if ${zfs} list -H -o name ${ds} > /dev/null 2>&1; then
            ${zfs} set com.sun:auto-snapshot=${val} ${ds}
          else
            echo "zfsAutoSnapshot: dataset ${ds} not found, skipping" >&2
          fi
        '';
      in ''
        ${setSnapshot cfg.autoSnapshot.poolName "false"}
        ${setSnapshot "${cfg.autoSnapshot.poolName}/persist" "true"}
      ''
    );
  };
}
