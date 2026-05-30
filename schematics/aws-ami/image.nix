# AWS image builder override.
# make-single-disk-zfs-image.nix uses a BIOS layout (bios_grub + plain FAT32).
# systemd-boot refuses a non-ESP partition, so GRUB is forced here.
# GRUB uses partition UUIDs, so it boots correctly on nvme0n1, xvda, etc.
{ config, lib, pkgs, ... }:
{
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  boot.loader.grub = {
    enable = lib.mkForce true;
    device = lib.mkForce "/dev/vda";
  };

  fileSystems = {
    "/" = {
      device = "vmpool/root";
      fsType = "zfs";
      neededForBoot = true;
    };
    "/nix" = {
      device = "vmpool/nix";
      fsType = "zfs";
    };
    "/boot" = lib.mkForce {
      device = "/dev/disk/by-label/ESP";
      fsType = "vfat";
    };
  };

  system.build.awsImage = pkgs.callPackage (pkgs.path + "/nixos/lib/make-single-disk-zfs-image.nix") {
    inherit pkgs lib config;
    format = "raw";
    rootPoolName = "vmpool";
    rootSize = 4096;
    memSize = 4096;
    includeChannel = false;
    datasets = {
      "vmpool/root" = {
        mount = "/";
        properties.mountpoint = "legacy";
      };
      "vmpool/nix" = {
        mount = "/nix";
        properties = {
          mountpoint = "legacy";
          atime = "off";
        };
      };
      "vmpool/persist" = {
        mount = "/persist";
        properties.mountpoint = "legacy";
      };
    };
  };
}
