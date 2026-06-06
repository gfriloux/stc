{ config, lib, pkgs, ... }:

let
  cfg = config.stc.relics.aws;
in
{
  imports = [
    (lib.mkRenamedOptionModule [ "stc" "aws" "enable" ] [ "stc" "relics" "aws" "enable" ])
    (lib.mkRenamedOptionModule [ "stc" "aws" "poolName" ] [ "stc" "relics" "aws" "poolName" ])
    (lib.mkRenamedOptionModule [ "stc" "aws" "ebsDisk" ] [ "stc" "relics" "aws" "ebsDisk" ])
    (lib.mkRenamedOptionModule [ "stc" "aws" "ebsPartition" ] [ "stc" "relics" "aws" "ebsPartition" ])
  ];

  options.stc.relics.aws = {
    enable = lib.mkEnableOption "AWS EC2 platform configuration (drivers, NTP, serial console, EBS grow)";

    poolName = lib.mkOption {
      type = lib.types.str;
      description = "ZFS pool name to expand when the EBS volume is larger than the built image.";
    };

    ebsDisk = lib.mkOption {
      type = lib.types.str;
      default = "nvme0n1";
      description = "EBS block device name (without /dev/). nvme0n1 for Nitro instances, xvda for Xen.";
    };

    ebsPartition = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = "Partition number holding the ZFS pool on the EBS disk. make-single-disk-zfs-image.nix creates bios_grub(1) + ESP(2) + ZFS(3).";
    };
  };

  config = lib.mkIf cfg.enable {
    boot = {
      # ---------------------------------------------------------------------------
      # Block device drivers
      #
      # Nitro instances : nvme (disk) + ena (network)
      # Xen instances   : xen_blkfront (disk) + xen_netfront (network)
      # ---------------------------------------------------------------------------
      initrd.availableKernelModules = [ "nvme" "ena" "xen_blkfront" ];
      kernelModules = [ "ena" "xen_netfront" ];

      # xen_fbfront causes a 30-second boot delay on Xen instances.
      blacklistedKernelModules = [ "xen_fbfront" ];

      kernelParams = [
        # Required for AWS serial console output (EC2 Connect, CloudWatch).
        "console=ttyS0,115200n8"
        # Amazon recommendation for EBS NVMe reliability.
        # https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/nvme-ebs-volumes.html
        "nvme_core.io_timeout=4294967295"
        "random.trust_cpu=on"
      ];

      # EBS volumes have no by-id entries — use /dev directly like QEMU virtio.
      zfs.devNodes = "/dev";
    };

    # AWS internal NTP endpoint — always reachable from EC2, no internet required.
    networking.timeServers = [ "169.254.169.123" ];

    # Serial console service — pairs with console=ttyS0 above.
    systemd.services."serial-getty@ttyS0".enable = true;

    # udisks2 pulls in GTK as a dependency — not acceptable on a headless server.
    services.udisks2.enable = false;

    # EC2 instance metadata and udev rules for NVMe device naming.
    services.udev.packages = [ pkgs.amazon-ec2-utils ];

    # Expand the ZFS pool to fill the EBS volume when it is larger than the image.
    # Idempotent: || true absorbs the no-op exit code when already at full size.
    system.activationScripts.growPart = ''
      ${pkgs.cloud-utils}/bin/growpart /dev/${cfg.ebsDisk} ${toString cfg.ebsPartition} || true
      ${pkgs.zfs}/bin/zpool online -e ${cfg.poolName} /dev/${cfg.ebsDisk}p${toString cfg.ebsPartition} || true
    '';
  };
}
