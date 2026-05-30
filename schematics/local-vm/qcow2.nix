# qcow2 builder override for QEMU local VM.
#
# make-single-disk-zfs-image.nix uses a BIOS layout (bios_grub + plain FAT32).
# systemd-boot refuses a non-ESP partition, so GRUB is forced here.
# This only applies to the image build — the live system uses systemd-boot.
{ config, lib, pkgs, ... }:
{
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  boot.loader.grub = {
    enable = lib.mkForce true;
    device = lib.mkForce "/dev/vda";
  };

  fileSystems."/boot" = lib.mkForce {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };

  system.build.qcow2 = pkgs.callPackage (pkgs.path + "/nixos/lib/make-single-disk-zfs-image.nix") {
    inherit pkgs lib config;
    format = "qcow2";
    rootPoolName = "vmpool";
    rootSize = 20480;
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
