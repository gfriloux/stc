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
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.stc.relics.impermanence;
  # Markers dropped in /run for the booted system to find. The initrd rbind-mounts
  # its /run onto /sysroot/run ("We need to propagate /run", nixpkgs
  # systemd/initrd.nix), so anything written here survives switch-root — which is
  # the only way this unit can say anything at all to userspace. Measured: it has
  # no fragment in the booted system (LoadState=not-found), so it never shows up
  # reliably in `systemctl --failed` on its own.
  failedMarker = "/run/stc-impermanence-rollback-failed";
  blankCreatedMarker = "/run/stc-impermanence-blank-created";

  rollbackScript = pkgs.writeShellScript "zfs-rollback" ''
    # writeShellScript emits only a runtimeShell shebang — no options — so
    # without this line the script runs on past its own failures.
    set -euo pipefail

    dataset="${cfg.poolName}/${cfg.datasetName}"
    snapshot="$dataset@blank"

    fail() {
      echo "impermanence: $1" >&2
      touch ${failedMarker} || true
      exit 1
    }

    # The dataset first, and deliberately not the snapshot. Checking only the
    # snapshot conflates "the reference is missing" with "the pool was never
    # imported" — and the second must never lead to taking a new reference.
    ${pkgs.zfs}/bin/zfs list -H -o name "$dataset" >/dev/null ||
      fail "$dataset is not available; is the pool imported?"

    if ! ${pkgs.zfs}/bin/zfs list -H -o name "$snapshot" >/dev/null 2>&1; then
      # Normal exactly once, on the very first boot of a fresh disk: the image
      # builder ships no snapshot (measured — make-single-disk-zfs-image.nix
      # contains no `zfs snapshot` at all). Anything later means the reference
      # was lost, and whatever is in the root dataset right now silently becomes
      # the new definition of "clean". The relic cannot tell those two apart, so
      # it says so instead of guessing.
      echo "impermanence: $snapshot is missing; creating it from the CURRENT" \
           "state of $dataset, which becomes the permanent clean reference" >&2
      touch ${blankCreatedMarker} || true
      ${pkgs.zfs}/bin/zfs snapshot "$snapshot" ||
        fail "could not create $snapshot"
    fi

    ${pkgs.zfs}/bin/zfs rollback -r "$snapshot" ||
      fail "could not roll $dataset back to @blank; the root is NOT clean"
  '';
in {
  imports = [
    (lib.mkRenamedOptionModule ["stc" "impermanence" "enable"] ["stc" "relics" "impermanence" "enable"])
    (lib.mkRenamedOptionModule ["stc" "impermanence" "poolName"] ["stc" "relics" "impermanence" "poolName"])
    (lib.mkRenamedOptionModule ["stc" "impermanence" "datasetName"] ["stc" "relics" "impermanence" "datasetName"])
    (lib.mkRenamedOptionModule ["stc" "impermanence" "persistPath"] ["stc" "relics" "impermanence" "persistPath"])
    (lib.mkRenamedOptionModule ["stc" "impermanence" "extraDirectories"] ["stc" "relics" "impermanence" "extraDirectories"])
    (lib.mkRenamedOptionModule ["stc" "impermanence" "extraFiles"] ["stc" "relics" "impermanence" "extraFiles"])
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
      default = [];
      description = "Additional directories under persistPath to bind-mount into /.";
    };

    extraFiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Additional files under persistPath to bind-mount into /.";
    };

    onRollbackFailure = lib.mkOption {
      type = lib.types.enum ["continue" "emergency"];
      default = "continue";
      description = ''
        What a failed rollback does to the boot.

        `continue` (default) — the boot proceeds. The host comes up with
        whatever the previous boot left in the root dataset, so it is **not**
        clean, but it is reachable. The failure is not silent: it is reported
        by `stc-impermanence-state.service` in the booted system, which fails
        and turns `systemctl is-system-running` to `degraded`.

        `emergency` — the rollback service pulls in `emergency.target` from the
        initrd and the boot stops. Integrity over availability: a host that
        cannot guarantee a clean root does not come up at all.

        Know the price before choosing `emergency` on a server:
        `boot.initrd.systemd.emergencyAccess` defaults to `null`, which means
        **no shell** at the emergency prompt. A headless host that lands there
        is one you have to reach out of band. Set `emergencyAccess` alongside
        it if you want to be able to take over.
      '';
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
      storePaths = [rollbackScript];

      services.zfs-rollback = {
        description = "Rollback ${cfg.poolName}/${cfg.datasetName} to @blank";
        wantedBy = ["initrd.target"];
        after = ["zfs-import-${cfg.poolName}.service"];
        before = ["sysroot.mount"];
        unitConfig =
          {
            DefaultDependencies = "no";
          }
          // lib.optionalAttrs (cfg.onRollbackFailure == "emergency") {
            OnFailure = "emergency.target";
            OnFailureJobMode = "replace-irreversibly";
          };
        serviceConfig = {
          Type = "oneshot";
          ExecStart = rollbackScript;
        };
      };
    };

    # -------------------------------------------------------------------------
    # Carry the initrd's verdict into the booted system.
    #
    # Without this the rollback can fail and leave almost no trace: the unit
    # above exists only in the initrd, so it has no fragment after switch-root
    # and does not reliably show up in `systemctl --failed`. The markers it
    # drops in /run do survive, because the initrd rbind-mounts /run onto
    # /sysroot/run — so a four-line unit here is what turns a silent dirty boot
    # into a named, failed unit and a `degraded` system.
    # -------------------------------------------------------------------------
    systemd.services.stc-impermanence-state = {
      description = "Report the outcome of the initrd impermanence rollback";
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        if [ -e ${blankCreatedMarker} ]; then
          echo "impermanence: ${cfg.poolName}/${cfg.datasetName}@blank was" \
               "(re)created this boot. Expected on a host's first boot;" \
               "anything else means the clean reference was lost and the" \
               "CURRENT root is now what every later boot rolls back to." >&2
        fi

        if [ -e ${failedMarker} ]; then
          echo "impermanence: the initrd rollback FAILED. This root was not" \
               "restored, so it still carries whatever the previous boot left" \
               "in it. See journalctl -b -u zfs-rollback.service." >&2
          exit 1
        fi
      '';
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

      directories =
        [
          "/var/lib/nixos"
          "/var/log"
        ]
        ++ cfg.extraDirectories;

      files =
        [
          "/etc/machine-id"
          "/etc/ssh/ssh_host_rsa_key"
          "/etc/ssh/ssh_host_rsa_key.pub"
          "/etc/ssh/ssh_host_ed25519_key"
          "/etc/ssh/ssh_host_ed25519_key.pub"
        ]
        ++ cfg.extraFiles;
    };
  };
}
