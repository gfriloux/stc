# Relic: ZFS Impermanence
# Every boot is a fresh start. The machine forgets. Only /persist remembers.
#
# On first boot, a @blank snapshot is taken of the root dataset.
# On every subsequent boot, root is rolled back to that snapshot before
# mounting — giving you a guaranteed-clean system state each time.
#
# Explicit persistence: anything you want to survive a reboot must be
# declared in extraDirectories or extraFiles. If it's not listed, it's gone.
# This is a feature, not a bug.
{ config, lib, pkgs, ... }:

let
  cfg = config.stc.relics.impermanence;
  rollbackScript = pkgs.writeShellScript "zfs-rollback" ''
      snapshot="${cfg.poolName}/${cfg.datasetName}@blank"
      if ! ${pkgs.zfs}/bin/zfs list "$snapshot" 2>/dev/null; then
        ${pkgs.zfs}/bin/zfs snapshot "$snapshot"
      fi
      ${pkgs.zfs}/bin/zfs rollback -r "$snapshot"
    '';
in
{
  imports = [
    (lib.mkRenamedOptionModule [ "stc" "impermanence" "enable" ] [ "stc" "relics" "impermanence" "enable" ])
    (lib.mkRenamedOptionModule [ "stc" "impermanence" "poolName" ] [ "stc" "relics" "impermanence" "poolName" ])
    (lib.mkRenamedOptionModule [ "stc" "impermanence" "datasetName" ] [ "stc" "relics" "impermanence" "datasetName" ])
    (lib.mkRenamedOptionModule [ "stc" "impermanence" "persistPath" ] [ "stc" "relics" "impermanence" "persistPath" ])
    (lib.mkRenamedOptionModule [ "stc" "impermanence" "extraDirectories" ] [ "stc" "relics" "impermanence" "extraDirectories" ])
    (lib.mkRenamedOptionModule [ "stc" "impermanence" "extraFiles" ] [ "stc" "relics" "impermanence" "extraFiles" ])
  ];

  options.stc.relics.impermanence = {
    enable = lib.mkEnableOption "ZFS-based impermanence (rollback root dataset at every boot)";

    poolName = lib.mkOption {
      type = lib.types.str;
      default = "rpool";
      description = "Name of the ZFS pool containing the root dataset.";
    };

    datasetName = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "Name of the ZFS dataset to roll back on each boot. The @blank snapshot is created automatically on first boot if absent.";
    };

    persistPath = lib.mkOption {
      type = lib.types.str;
      default = "/persist";
      description = "Mount point of the persistent ZFS dataset.";
    };

    persistDataset = lib.mkOption {
      type = lib.types.str;
      default = "persist";
      description = "Name of the persistent ZFS dataset under poolName, mounted at persistPath.";
    };

    extraDirectories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional directories under persistPath to bind-mount into /.";
    };

    extraFiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional files under persistPath to bind-mount into /.";
    };
  };

  config = lib.mkIf cfg.enable {
    # -------------------------------------------------------------------------
    # Roll back the root dataset to @blank at every boot.
    #
    # systemd stage-1 initrd is required: postDeviceCommands is not available
    # in the systemd initrd path. The service runs after pool import and before
    # root mount, so the dataset is clean before userspace reads it.
    # -------------------------------------------------------------------------
    boot.initrd.systemd = {
      enable = true;
      storePaths = [ rollbackScript ];

      services.zfs-rollback = {
        description = "Rollback ${cfg.poolName}/${cfg.datasetName} to @blank";
        wantedBy = [ "initrd.target" ];
        after = [ "zfs-import-${cfg.poolName}.service" ];
        before = [ "sysroot.mount" ];
        unitConfig.DefaultDependencies = "no";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = rollbackScript;
        };
      };
    };

    # The persistent dataset must be available early so SSH host keys,
    # machine-id, and other state are readable during boot.
    fileSystems."${cfg.persistPath}" = {
      device = "${cfg.poolName}/${cfg.persistDataset}";
      fsType = "zfs";
      neededForBoot = true;
    };

    # -------------------------------------------------------------------------
    # Paths that must survive reboots.
    #
    #   /etc/machine-id         — stable systemd identity (journald breaks if this changes)
    #   /etc/ssh/ssh_host_*     — SSH host keys (changes break client known_hosts)
    #   /var/lib/nixos          — NixOS UID/GID tracking across activations
    #   /var/log                — persistent logs for audit and debugging
    # -------------------------------------------------------------------------
    environment.persistence."${cfg.persistPath}" = {
      hideMounts = true;

      directories = [
        "/var/lib/nixos"
        "/var/log"
      ] ++ cfg.extraDirectories;

      files = [
        "/etc/machine-id"
        "/etc/ssh/ssh_host_rsa_key"
        "/etc/ssh/ssh_host_rsa_key.pub"
        "/etc/ssh/ssh_host_ed25519_key"
        "/etc/ssh/ssh_host_ed25519_key.pub"
      ] ++ cfg.extraFiles;
    };
  };
}
