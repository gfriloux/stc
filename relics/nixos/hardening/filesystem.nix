{
  config,
  lib,
  ...
}: let
  cfg = config.stc.relics.hardening.filesystem;

  # /var/tmp entries of the impermanence module, when it is imported at all:
  # `?` rather than mkIf, since mkIf false does not shield an unknown option.
  persistedVarTmp = lib.optionals (config.environment ? persistence) (
    lib.concatMap (p: lib.filter (d: d.dirPath == "/var/tmp") p.directories)
    (lib.attrValues config.environment.persistence)
  );
in {
  imports = [
    (lib.mkRenamedOptionModule ["stc" "hardening" "filesystem" "enable"] ["stc" "relics" "hardening" "filesystem" "enable"])
    (lib.mkRenamedOptionModule ["stc" "hardening" "filesystem" "tmpSize"] ["stc" "relics" "hardening" "filesystem" "tmpSize"])
    (lib.mkRenamedOptionModule ["stc" "hardening" "filesystem" "shmSize"] ["stc" "relics" "hardening" "filesystem" "shmSize"])
    (lib.mkRenamedOptionModule ["stc" "hardening" "filesystem" "gaming"] ["stc" "relics" "hardening" "filesystem" "gaming"])
  ];

  options.stc.relics.hardening.filesystem = {
    enable = lib.mkEnableOption "filesystem hardening (/tmp and /var/tmp noexec, /proc hidepid, /dev/shm restricted)";

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

    varTmp.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Remount /var/tmp onto itself with nosuid, nodev and noexec. Unlike /tmp
        it stays on disk, so its contents still survive a reboot. Set false if
        your own layout already mounts /var/tmp: both definitions would
        otherwise conflict at evaluation.
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
        - /var/tmp is mounted without noexec, for consistency with /tmp.
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
      # ANSSI-BP-028 R28 — /tmp: nosuid,nodev,noexec
      "/tmp" = lib.mkForce {
        device = "tmpfs";
        fsType = "tmpfs";
        options =
          ["defaults" "nosuid" "nodev" "size=${cfg.tmpSize}" "mode=1777"]
          ++ lib.optional (!cfg.gaming) "noexec";
      };

      # /var/tmp bound onto itself, so the hardening needs no knowledge of the
      # disk layout and the directory keeps whatever persistence the layout
      # gives it (FHS: survives a reboot) — binding it to the /tmp tmpfs would
      # break both. On an impermanence host it lives on the rolled-back root,
      # so it is wiped at boot, as before; persisting it is refused below. X-mount.mkdir
      # because on an impermanence host / is rolled back before this mount and
      # /var/tmp may not exist yet; systemd-tmpfiles then sets its 1777 mode.
      # Builds are unaffected: nix-daemon builds under /nix/var/nix/builds.
      # ANSSI-BP-028 R28 — /var/tmp: nosuid,nodev,noexec
      "/var/tmp" = lib.mkIf cfg.varTmp.enable {
        device = "/var/tmp";
        fsType = "none";
        options =
          ["bind" "X-mount.mkdir" "nosuid" "nodev"]
          ++ lib.optional (!cfg.gaming) "noexec";
      };

      # hidepid=2 hides other users' processes. gid=proc is required so that
      # systemd-logind and other system services can still inspect all PIDs.
      # ANSSI-BP-028 R28 — /proc: hidepid=2
      "/proc" = {
        device = "proc";
        fsType = "proc";
        options = ["nosuid" "noexec" "nodev" "hidepid=2" "gid=proc"];
      };

      # noexec and size cap on /dev/shm.
      # When gaming = true, noexec is omitted: DXVK and VKD3D-Proton map
      # executable code into shared memory. Also raise shmSize for heavy workloads.
      # ANSSI-BP-028 R28 spirit — /dev/shm is not in the R28 table but shares its rationale.
      "/dev/shm" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options =
          ["defaults" "nosuid" "nodev" "size=${cfg.shmSize}"]
          ++ lib.optional (!cfg.gaming) "noexec";
      };
    };

    # Persisting /var/tmp through impermanence puts a var-tmp.mount unit in
    # /etc/systemd/system, which shadows the fstab-generated one: /var/tmp would
    # come from the persist path with exec allowed, and nothing would say so.
    assertions = [
      {
        assertion = !cfg.varTmp.enable || persistedVarTmp == [];
        message = ''
          stc.relics.hardening.filesystem: /var/tmp is both hardened (varTmp.enable)
          and persisted through environment.persistence. The persistence bind
          mount would replace the hardened one, silently dropping nosuid, nodev and
          noexec. Either stop persisting /var/tmp, or set
          stc.relics.hardening.filesystem.varTmp.enable = false to accept /var/tmp
          without these flags.
        '';
      }
    ];

    # Group required by hidepid=2,gid=proc — members bypass the process hide.
    users.groups.proc = {};

    # logind manages sessions and needs to see all PIDs to function correctly.
    systemd.services.systemd-logind.serviceConfig.SupplementaryGroups = ["proc"];

    # hidepid=2 also breaks anything that expects to see other users' processes:
    # polkit, user D-Bus agents and several Prometheus exporters. logind is
    # handled above; on a desktop or monitored host, add the relevant services
    # to the "proc" group (SupplementaryGroups) too. Warn rather than guess.
    warnings =
      lib.optional
      # `||` not `or`: `or` is attribute-selection-with-default, and since
      # services.xserver.enable always exists it would collapse to that single
      # value — never firing for the plasma6 relic, which sets xserver.enable = false.
      (config.services.xserver.enable || config.services.desktopManager.plasma6.enable)
      ''
        stc.relics.hardening.filesystem enables hidepid=2 on /proc and a desktop
        is also enabled. polkit, user D-Bus agents and some exporters may misbehave
        because they cannot see other users' processes. Add the affected services
        to the "proc" group via systemd SupplementaryGroups (as done here for
        systemd-logind), or disable filesystem hardening on desktop hosts.
      '';
  };
}
