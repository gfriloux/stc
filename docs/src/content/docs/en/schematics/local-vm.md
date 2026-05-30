---
title: local-vm
description: A QEMU/KVM NixOS development VM with ZFS, impermanence, and full hardening.
---

**Source:** `schematics/local-vm/`

A local QEMU/KVM virtual machine running NixOS with ZFS storage, impermanence
(root rolls back to `@blank` on every boot), and full hardening. Use this as a
development or staging VM.

## Prerequisites

- Nix with flakes enabled
- KVM-capable host (`/dev/kvm` accessible)
- qemu is not required on the host — the `just run` recipe provides it via `nix shell`

## Modules Used

| Module | Purpose |
|--------|---------|
| `disko.nixosModules.disko` | Declarative disk partitioning |
| `stc.nixosModules.relics-boot` | systemd-boot + EFI |
| `stc.nixosModules.relics-zfs` | ZFS-compatible kernel, auto-scrub, TRIM, ZED |
| `stc.nixosModules.relics-networking` | DHCP, Quad9 DNS |
| `stc.nixosModules.relics-impermanence` | Root rollback on each boot |
| `stc.nixosModules.cogitator-hardening` | Full hardening suite |
| `stc.nixosModules.cogitator-vm` | fish, SSH, admin user, optional Docker, Nix GC |
| `stc.lib.layouts.zfs-local-vm` | EFI + ZFS disk layout |
| `./qcow2.nix` | qcow2 image builder (GRUB override for build) |

## Critical QEMU Configuration

Two settings are mandatory for virtio-based QEMU VMs:

```nix
# virtio drivers must be loaded in the initrd so /dev/vda exists
# before ZFS tries to import the pool.
boot.initrd.kernelModules = [ "virtio_pci" "virtio_blk" ];

# QEMU virtio disks have no /dev/disk/by-id/ entries.
# ZFS defaults to searching there — redirect it to /dev.
boot.zfs.devNodes = "/dev";
```

Without `virtio_pci` and `virtio_blk` in the initrd, the disk is invisible when
ZFS tries to import the pool and the VM will not boot. Without `devNodes = "/dev"`,
ZFS will fail to find the pool by the device path it expects.

## Justfile Recipes

### Full VM with ZFS

```bash
just build    # builds the qcow2 image (~5-10 minutes first time)
just run      # boots it with QEMU/KVM, SSH on port 2222
just ssh      # SSH into the running VM as admin
```

`run` uses `snapshot=on` — the Nix store image is kept read-only and every boot
starts from the same base. Your changes to `/persist` survive because they are
on the persistent dataset, but nothing else does.

### Developer Recipes

```bash
just fmt          # alejandra format
just fmt-check    # check without modifying
just lint         # statix + deadnix
just ci           # fmt-check + lint
just check        # nix flake check --show-trace
```

## Complete flake.nix

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    stc = {
      url = "github:gfriloux/stc";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko.follows = "stc/disko";
  };

  outputs = { nixpkgs, stc, disko, ... }: {
    nixosConfigurations.local-vm = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko
        stc.nixosModules.relics-boot
        stc.nixosModules.relics-zfs
        stc.nixosModules.relics-networking
        stc.nixosModules.relics-impermanence
        stc.nixosModules.cogitator-hardening
        stc.nixosModules.cogitator-vm
        (stc.lib.layouts.zfs-local-vm { poolName = "vmpool"; })
        ./qcow2.nix
        ({ ... }: {
          stc = {
            boot.enable = true;
            zfs.enable = true;
            networking.enable = true;
            hardening.enable = true;
            impermanence = {
              enable = true;
              poolName = "vmpool";
              extraDirectories = [ "/var/db/sudo/lectured" ];
            };
            cogitator.vm = {
              enable = true;
              username = "admin";
              authorizedKeys = [
                # "ssh-ed25519 AAAA... you@host"
              ];
              docker.enable = false;
            };
          };

          boot.initrd.kernelModules = [ "virtio_pci" "virtio_blk" ];
          boot.zfs.devNodes = "/dev";

          networking.hostName = "local-vm";
          networking.hostId = "deadc0de";  # replace with your own

          users.mutableUsers = false;
          users.users.admin.initialPassword = "changeme";
          users.users.root.initialPassword = "changeme";
          security.sudo.wheelNeedsPassword = false;

          time.timeZone = "UTC";
          system.stateVersion = "24.11";
        })
      ];
    };
  };
}
```

:::caution[Change the hostId]
`networking.hostId = "deadc0de"` is a placeholder. Every ZFS machine must have a
unique hostId. Generate one: `head -c4 /dev/urandom | od -A none -t x4 | tr -d ' \n'`
:::

## qcow2.nix

The `qcow2.nix` module overrides the boot loader for the image build. The NixOS
`make-single-disk-zfs-image.nix` builder uses a BIOS partition layout, and
systemd-boot refuses to install there. GRUB is forced for the image build only;
the live system still uses systemd-boot.

## See Also

- [Forge — Layouts](/en/forge/layouts/) — the `zfs-local-vm` disk layout
- [relics-impermanence](/en/relics/impermanence/) — how the rollback works
- [cogitator-vm](/en/cogitator/vm/) — the VM base profile options
