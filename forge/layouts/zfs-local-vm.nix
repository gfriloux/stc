# Forge Layout: ZFS Local VM
# Disk layout for a QEMU/KVM local virtual machine.
#
# Device: /dev/vda (virtio-blk)
# Partitions:
#   [EFI 1G vfat /boot] [ZFS remainder]
#
# ZFS pool (vmpool):
#   vmpool/root    → /        ephemeral — rolled back to @blank at every boot
#   vmpool/nix     → /nix     persistent — the Nix store does not forget
#   vmpool/persist → /persist persistent — explicit state only
#
# Pair with: stc.boot.enable + stc.impermanence.enable (poolName = "vmpool")
{ poolName ? "vmpool" }:
{
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
              mountpoint = "/boot";
            };
          };

          zfs = {
            size = "100%";
            content = {
              type = "zfs";
              pool = poolName;
            };
          };
        };
      };
    };

    zpool.${poolName} = {
      type = "zpool";

      options = {
        ashift = "12"; # 4K sector alignment
      };

      rootFsOptions = {
        compression = "lz4";
        atime = "off";
        mountpoint = "none"; # all datasets use legacy mountpoints
        xattr = "sa"; # store xattrs in inodes for performance
        acltype = "posixacl";
      };

      datasets = {
        root = {
          type = "zfs_fs";
          mountpoint = "/";
          options.mountpoint = "legacy";
          postCreateHook = "zfs snapshot ${poolName}/root@blank";
        };

        nix = {
          type = "zfs_fs";
          mountpoint = "/nix";
          options = {
            mountpoint = "legacy";
            atime = "off";
          };
        };

        persist = {
          type = "zfs_fs";
          mountpoint = "/persist";
          options.mountpoint = "legacy";
        };
      };
    };
  };
}
