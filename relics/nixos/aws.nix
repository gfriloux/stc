{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.stc.relics.aws;
in {
  imports = [
    (lib.mkRenamedOptionModule ["stc" "aws" "enable"] ["stc" "relics" "aws" "enable"])
    (lib.mkRenamedOptionModule ["stc" "aws" "poolName"] ["stc" "relics" "aws" "poolName"])
    (lib.mkRenamedOptionModule ["stc" "aws" "ebsDisk"] ["stc" "relics" "aws" "ebsDisk"])
    (lib.mkRenamedOptionModule ["stc" "aws" "ebsPartition"] ["stc" "relics" "aws" "ebsPartition"])
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
      initrd.availableKernelModules = ["nvme" "ena" "xen_blkfront"];
      kernelModules = ["ena" "xen_netfront"];

      # xen_fbfront causes a 30-second boot delay on Xen instances.
      blacklistedKernelModules = ["xen_fbfront"];

      kernelParams = [
        # Required for AWS serial console output (EC2 Connect, CloudWatch).
        "console=ttyS0,115200n8"
        # Amazon recommendation for EBS NVMe reliability.
        # https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/nvme-ebs-volumes.html
        "nvme_core.io_timeout=4294967295"
        # Trust the CPU RNG (RDRAND) to seed the kernel entropy pool, avoiding
        # slow first-boot entropy starvation on headless EC2 instances. Trade-off:
        # it places trust in the CPU vendor's RNG. Reasonable on a cloud host where
        # you already trust the hypervisor; remove it if your threat model differs.
        "random.trust_cpu=on"
      ];

      # EBS volumes have no by-id entries — use /dev directly like QEMU virtio.
      zfs.devNodes = "/dev";
    };

    # AWS internal NTP endpoint — always reachable from EC2, no internet required.
    networking.timeServers = ["169.254.169.123"];

    # Serial console service — pairs with console=ttyS0 above.
    systemd.services."serial-getty@ttyS0".enable = true;

    # udisks2 pulls in GTK as a dependency — not acceptable on a headless server.
    services.udisks2.enable = false;

    # EC2 instance metadata and udev rules for NVMe device naming.
    services.udev.packages = [pkgs.amazon-ec2-utils];

    # Expand the ZFS pool to fill the EBS volume when it is larger than the image.
    #
    # A boot-time oneshot rather than an activation script: activation scripts
    # also run on every `nixos-rebuild switch`, and the previous `|| true` masked
    # genuine failures. growpart exits 1 when there is nothing to grow (a no-op,
    # not an error) and ≥2 on real failure — we only tolerate the former.
    systemd.services.stc-grow-pool = {
      description = "Grow root partition and expand the ZFS pool to fill the disk";
      wantedBy = ["multi-user.target"];
      after = ["zfs-import.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        rc=0
        ${pkgs.cloud-utils}/bin/growpart /dev/${cfg.ebsDisk} ${toString cfg.ebsPartition} || rc=$?
        if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
          echo "growpart failed with exit code $rc" >&2
          exit "$rc"
        fi
        ${pkgs.zfs}/bin/zpool online -e ${cfg.poolName} /dev/${cfg.ebsDisk}p${toString cfg.ebsPartition}
      '';
    };
  };
}
