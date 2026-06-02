# Cogitator: Sarcophagus AWS
#
# Builds a NixOS raw disk image for import as an AWS AMI, with ZFS + impermanence.
# Composes: ZFS, networking, impermanence, AWS platform, and the full hardening suite.
# Disk layout: GPT on /dev/vda — 1G EFI + ZFS pool (root/nix/persist).
#
# At runtime on EC2, relics-aws expands the ZFS pool to fill the EBS volume,
# configures NVMe/ENA drivers, NTP, and serial console.
#
# Usage:
#   stc.cogitator.sarcophagus-aws.enable = true;
#   system.build.awsImage  →  nix build .#nixosConfigurations.<name>.config.system.build.awsImage
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.stc.cogitator.sarcophagus-aws;
in {
  imports = [
    ../../relics/nixos/zfs.nix
    ../../relics/nixos/networking.nix
    ../../relics/nixos/impermanence.nix
    ../../relics/nixos/aws.nix
    ./hardening.nix
  ];

  options.stc.cogitator.sarcophagus-aws = {
    enable = lib.mkEnableOption "AWS AMI NixOS disk image with ZFS + impermanence";

    poolName = lib.mkOption {
      type = lib.types.str;
      default = "vmpool";
      description = "ZFS pool name used for the root, nix, and persist datasets.";
    };

    rootSize = lib.mkOption {
      type = lib.types.int;
      default = 4096;
      description = "Disk image size in MiB.";
    };

    memSize = lib.mkOption {
      type = lib.types.int;
      default = 4096;
      description = "Build VM memory in MiB.";
    };

    ebsDisk = lib.mkOption {
      type = lib.types.str;
      default = "nvme0n1";
      description = "EBS block device name (without /dev/). nvme0n1 for Nitro instances, xvda for Xen.";
    };

    ebsPartition = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = "Partition number holding the ZFS pool. make-single-disk-zfs-image.nix creates bios_grub(1) + ESP(2) + ZFS(3).";
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
    stc.zfs.enable = true;
    stc.networking.enable = true;
    stc.hardening.enable = true;
    stc.impermanence = {
      enable = true;
      poolName = cfg.poolName;
      inherit (cfg.impermanence) extraDirectories extraFiles;
    };
    stc.aws = {
      enable = true;
      poolName = cfg.poolName;
      inherit (cfg) ebsDisk ebsPartition;
    };

    # make-single-disk-zfs-image.nix creates a BIOS layout (bios_grub partition +
    # plain FAT32 /boot). GRUB is installed to /dev/vda during build; at runtime
    # on AWS the disk is /dev/nvme0n1 or /dev/xvda, but GRUB uses partition UUIDs
    # internally so it boots correctly regardless of the device name.
    boot.loader = {
      systemd-boot.enable = lib.mkForce false;
      efi.canTouchEfiVariables = lib.mkForce false;
      grub = {
        enable = lib.mkForce true;
        device = lib.mkForce "/dev/vda";
      };
    };

    # Filesystem declarations matching the ZFS datasets below.
    # neededForBoot = true on / ensures the pool is imported before sysroot.mount.
    fileSystems = {
      "/" = {
        device = "${cfg.poolName}/root";
        fsType = "zfs";
        neededForBoot = true;
      };
      "/nix" = {
        device = "${cfg.poolName}/nix";
        fsType = "zfs";
      };
      "/boot" = lib.mkForce {
        device = "/dev/disk/by-label/ESP";
        fsType = "vfat";
      };
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

    system.build.awsImage = pkgs.callPackage (pkgs.path + "/nixos/lib/make-single-disk-zfs-image.nix") {
      inherit pkgs lib config;
      format = "raw";
      name = "nixos-aws-ami";
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
