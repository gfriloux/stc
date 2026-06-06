{ config, lib, ... }:

let
  cfg = config.stc.relics.hardening.filesystem;
in
{
  imports = [
    (lib.mkRenamedOptionModule [ "stc" "hardening" "filesystem" "enable" ] [ "stc" "relics" "hardening" "filesystem" "enable" ])
    (lib.mkRenamedOptionModule [ "stc" "hardening" "filesystem" "tmpSize" ] [ "stc" "relics" "hardening" "filesystem" "tmpSize" ])
    (lib.mkRenamedOptionModule [ "stc" "hardening" "filesystem" "shmSize" ] [ "stc" "relics" "hardening" "filesystem" "shmSize" ])
    (lib.mkRenamedOptionModule [ "stc" "hardening" "filesystem" "gaming" ] [ "stc" "relics" "hardening" "filesystem" "gaming" ])
  ];

  options.stc.relics.hardening.filesystem = {
    enable = lib.mkEnableOption "filesystem hardening (/tmp noexec, /proc hidepid, /dev/shm restricted)";

    tmpSize = lib.mkOption {
      type = lib.types.str;
      default = "2G";
      description = "Maximum size of the /tmp tmpfs. Capped to prevent OOM on memory-constrained systems.";
    };

    shmSize = lib.mkOption {
      type = lib.types.str;
      default = "256M";
      description = ''
        Maximum size of the /dev/shm tmpfs. The default 256M is appropriate for
        server workloads. DXVK and VKD3D-Proton use shared memory intensively —
        set to 2G or more when gaming = true.
      '';
    };

    gaming = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Relax filesystem restrictions incompatible with Steam and Proton.
        When true:
        - /tmp is mounted without noexec (Wine/Proton extract and run binaries there).
        - /dev/shm is mounted without noexec (DXVK/VKD3D-Proton require exec in shm).
        The shmSize option still applies — increase it accordingly.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    fileSystems = {
      # noexec on /tmp closes the classic write-and-execute attack vector.
      # Defined explicitly here (not via boot.tmp.useTmpfs) so that the
      # security mount options are the only source of truth for this mount.
      # When gaming = true, noexec is omitted: Wine/Proton extract and execute
      # binaries under /tmp during game launches.
      "/tmp" = lib.mkForce {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [ "defaults" "nosuid" "nodev" "size=${cfg.tmpSize}" "mode=1777" ]
          ++ lib.optional (!cfg.gaming) "noexec";
      };

      # hidepid=2 hides other users' processes. gid=proc is required so that
      # systemd-logind and other system services can still inspect all PIDs.
      "/proc" = {
        device = "proc";
        fsType = "proc";
        options = [ "nosuid" "noexec" "nodev" "hidepid=2" "gid=proc" ];
      };

      # noexec and size cap on /dev/shm.
      # When gaming = true, noexec is omitted: DXVK and VKD3D-Proton map
      # executable code into shared memory. Also raise shmSize for heavy workloads.
      "/dev/shm" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [ "defaults" "nosuid" "nodev" "size=${cfg.shmSize}" ]
          ++ lib.optional (!cfg.gaming) "noexec";
      };
    };

    # Group required by hidepid=2,gid=proc — members bypass the process hide.
    users.groups.proc = { };

    # logind manages sessions and needs to see all PIDs to function correctly.
    systemd.services.systemd-logind.serviceConfig.SupplementaryGroups = [ "proc" ];
  };
}
