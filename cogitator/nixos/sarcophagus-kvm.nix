# Cogitator: Sarcophagus KVM
#
# Builds a QEMU/KVM NixOS disk image (qcow2) with ZFS + impermanence.
# Composes: ZFS, networking, impermanence, and the full hardening suite.
# Disk layout: GPT on /dev/vda — 1G EFI + ZFS pool (root/nix/persist).
#
# The image builder uses BIOS/GRUB (make-single-disk-zfs-image.nix requires it).
# At runtime, ZFS rolls back the root dataset to @blank on every boot.
#
# Usage:
#   stc.cogitator.sarcophagus-kvm.enable = true;
#   system.build.qcow2  →  nix build .#nixosConfigurations.<name>.config.system.build.qcow2
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.stc.cogitator.sarcophagus-kvm;
in {
  imports = [
    ../../relics/nixos/zfs.nix
    ../../relics/nixos/networking.nix
    ../../relics/nixos/impermanence.nix
    ./hardening.nix
  ];

  options.stc.cogitator.sarcophagus-kvm = {
    enable = lib.mkEnableOption "QEMU/KVM NixOS disk image with ZFS + impermanence";

    poolName = lib.mkOption {
      type = lib.types.str;
      default = "vmpool";
      description = "ZFS pool name used for the root, nix, and persist datasets.";
    };

    rootSize = lib.mkOption {
      type = lib.types.int;
      default = 20480;
      description = "Disk image size in MiB.";
    };

    memSize = lib.mkOption {
      type = lib.types.int;
      default = 4096;
      description = "Build VM memory in MiB.";
    };

    impermanence = {
      extraDirectories = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Additional directories under /persist to bind-mount into /.";
      };

      extraFiles = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Additional files under /persist to bind-mount into /.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    stc.relics.zfs.enable = true;
    stc.relics.networking.enable = true;
    stc.cogitator.hardening.enable = true;
    stc.relics.impermanence = {
      enable = true;
      poolName = cfg.poolName;
      inherit (cfg.impermanence) extraDirectories extraFiles;
    };

    # Virtio block driver must be loaded early so /dev/vda is present
    # before ZFS tries to import the pool.
    boot.initrd.kernelModules = [
      "virtio_pci"
      "virtio_blk"
    ];

    # Virtio disks have no by-id entries in QEMU.
    boot.zfs.devNodes = "/dev";

    # make-single-disk-zfs-image.nix creates a BIOS layout (bios_grub partition +
    # plain FAT32 /boot). systemd-boot refuses to install on a non-ESP partition.
    boot.loader = {
      systemd-boot.enable = lib.mkForce false;
      efi.canTouchEfiVariables = lib.mkForce false;
      grub = {
        enable = lib.mkForce true;
        device = lib.mkForce "/dev/vda";
      };
    };

    # /boot is plain FAT32 (labelled ESP by make-single-disk-zfs-image.nix,
    # but without the EFI partition type flag).
    fileSystems."/boot" = lib.mkForce {
      device = "/dev/disk/by-label/ESP";
      fsType = "vfat";
    };

    # Disk layout: GPT on /dev/vda
    #   Partition 1 — 1G FAT32 /boot (label: ESP)
    #   Partition 2 — remainder ZFS pool
    disko.devices = {
      disk.main = {
        type = "disk";
        device = "/dev/vda";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = lib.mkForce "/boot";
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = cfg.poolName;
              };
            };
          };
        };
      };

      zpool.${cfg.poolName} = {
        type = "zpool";
        options.ashift = "12";
        rootFsOptions = {
          compression = "lz4";
          atime = "off";
          mountpoint = "none";
          xattr = "sa";
          acltype = "posixacl";
        };
        datasets = {
          root = {
            type = "zfs_fs";
            mountpoint = lib.mkForce "/";
            options.mountpoint = "legacy";
            postCreateHook = "zfs snapshot ${cfg.poolName}/root@blank";
          };
          nix = {
            type = "zfs_fs";
            mountpoint = lib.mkForce "/nix";
            options = {
              mountpoint = "legacy";
              atime = "off";
            };
          };
          persist = {
            type = "zfs_fs";
            mountpoint = lib.mkForce "/persist";
            options.mountpoint = "legacy";
          };
        };
      };
    };

    system.build.qcow2 = pkgs.callPackage (pkgs.path + "/nixos/lib/make-single-disk-zfs-image.nix") {
      inherit pkgs lib config;
      format = "qcow2";
      rootPoolName = cfg.poolName;
      rootSize = cfg.rootSize;
      memSize = cfg.memSize;
      includeChannel = false;
      datasets = {
        "${cfg.poolName}/root" = {
          mount = "/";
          properties.mountpoint = "legacy";
        };
        "${cfg.poolName}/nix" = {
          mount = "/nix";
          properties = {
            mountpoint = "legacy";
            atime = "off";
          };
        };
        "${cfg.poolName}/persist" = {
          mount = "/persist";
          properties.mountpoint = "legacy";
        };
      };
    };
  };
}
