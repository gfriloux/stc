{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.stc.relics.aws;

  # Partition naming differs by device class: NVMe inserts a "p" before the
  # partition number (nvme0n1 -> nvme0n1p3), Xen virtual disks do not
  # (xvda -> xvda3). The rule is "p only when the device name ends in a digit",
  # which holds for nvme*/mmcblk* (p) and xvd*/sd*/vd* (no p). growpart takes the
  # disk and partition as separate arguments and is unaffected.
  partSep =
    if (builtins.match ".*[0-9]" cfg.ebsDisk) != null
    then "p"
    else "";
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
    #
    # This is a *fallback*, not a pin, and deliberately so. networking.timeServers
    # feeds services.timesyncd.fallbackServers, which renders FallbackNTP= — the
    # lowest-priority field (timesyncd.conf(5): per-interface servers from
    # systemd-networkd take precedence, "as do any servers set via NTP= above").
    # Measured on schematics/aws-ami: /etc/systemd/timesyncd.conf contains
    # FallbackNTP=169.254.169.123 and no NTP= line.
    #
    # That is the level we want. EC2 advertises this same endpoint over DHCP, so
    # the normal path never needs this line; it covers the instance whose lease
    # carries no NTP option. Pinning it via services.timesyncd.servers would
    # override a consumer running an authoritative time server in their own VPC.
    # Why no NTP relic exists at all: docs reference/anssi-bp-028 (issue #38).
    networking.timeServers = ["169.254.169.123"];

    # Serial console service — pairs with console=ttyS0 above.
    #
    # mkDefault, not a bare true: a real EC2 host wants this getty, but a VM that
    # owns ttyS0 for its own purposes must be able to take it. Measured — at
    # normal priority this collided head-on with the nixosTest instrumentation,
    # which claims the same port at the same priority ("has conflicting
    # definition values"), so no proving could boot a profile importing this
    # relic. mkDefault lets the caller win without mkForce and changes nothing
    # for a host that does not ask: the three schematics keep a byte-identical
    # drvPath. Do not "simplify" this back to true.
    systemd.services."serial-getty@ttyS0".enable = lib.mkDefault true;

    # udisks2 pulls in GTK as a dependency — not acceptable on a headless server.
    #
    # mkDefault, and the line is kept for what it documents rather than for what
    # it enforces. Measured: upstream already defaults services.udisks2.enable
    # to false (bare node, and the option's own default), so this never changed
    # an image STC builds. And at normal priority it did not keep GTK out
    # either — a consumer composing this relic with a desktop module that
    # enables udisks2 got "has conflicting definition values" and a stopped
    # build, not a headless server. Enforcing the intent would take mkForce,
    # which would break that consumer's desktop silently instead of telling
    # them. So: the intent stays readable, and whoever knowingly wants udisks2
    # on an EC2 host gets it with a plain definition.
    services.udisks2.enable = lib.mkDefault false;

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
        ${pkgs.zfs}/bin/zpool online -e ${cfg.poolName} /dev/${cfg.ebsDisk}${partSep}${toString cfg.ebsPartition}
      '';
    };
  };
}
