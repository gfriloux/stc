{ config, lib, ... }:

let
  cfg = config.stc.hardening.filesystem;
in
{
  options.stc.hardening.filesystem = {
    enable = lib.mkEnableOption "filesystem hardening (/tmp noexec, /proc hidepid, /dev/shm restricted)";

    tmpSize = lib.mkOption {
      type = lib.types.str;
      default = "2G";
      description = "Maximum size of the /tmp tmpfs. Capped to prevent OOM on memory-constrained systems.";
    };
  };

  config = lib.mkIf cfg.enable {
    fileSystems = {
      # noexec on /tmp closes the classic write-and-execute attack vector.
      # Defined explicitly here (not via boot.tmp.useTmpfs) so that the
      # security mount options are the only source of truth for this mount.
      "/tmp" = lib.mkForce {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [ "defaults" "nosuid" "noexec" "nodev" "size=${cfg.tmpSize}" "mode=1777" ];
      };

      # hidepid=2 hides other users' processes. gid=proc is required so that
      # systemd-logind and other system services can still inspect all PIDs.
      "/proc" = {
        device = "proc";
        fsType = "proc";
        options = [ "nosuid" "noexec" "nodev" "hidepid=2" "gid=proc" ];
      };

      "/dev/shm" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [ "defaults" "nosuid" "noexec" "nodev" "size=256M" ];
      };
    };

    # Group required by hidepid=2,gid=proc — members bypass the process hide.
    users.groups.proc = { };

    # logind manages sessions and needs to see all PIDs to function correctly.
    systemd.services.systemd-logind.serviceConfig.SupplementaryGroups = [ "proc" ];
  };
}
