---
title: local-vm
description: A QEMU/KVM NixOS development VM with ZFS, impermanence, and full hardening.
---

**Source:** `schematics/local-vm/`

A local QEMU/KVM virtual machine running NixOS with ZFS storage, impermanence
(root rolls back to `@blank` on every boot), and full hardening. Use this as a
development or staging VM.

This schematic uses [cogitator-sarcophagus-kvm](/stc/en/cogitator/sarcophagus-kvm/),
which embeds the disk layout, GRUB override, and qcow2 builder — no separate
`disko` import or `qcow2.nix` module required.

## Prerequisites

- Nix with flakes enabled
- KVM-capable host (`/dev/kvm` accessible)
- qemu is not required on the host — the `just run` recipe provides it via `nix shell`

## Modules Used

| Module | Purpose |
|--------|---------|
| `stc.nixosModules.cogitator-sarcophagus-kvm` | ZFS + impermanence + hardening + disk layout + qcow2 builder |
| `stc.nixosModules.cogitator-vm` | fish, SSH, admin user, optional Docker, Nix GC |

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
  };

  outputs = { nixpkgs, stc, ... }: {
    nixosConfigurations.local-vm = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        stc.nixosModules.cogitator-sarcophagus-kvm
        stc.nixosModules.cogitator-vm
        ({ ... }: {
          stc.cogitator.sarcophagus-kvm = {
            enable = true;
            impermanence.extraDirectories = [ "/var/db/sudo/lectured" ];
          };
          stc.cogitator.vm = {
            enable = true;
            username = "admin";
            authorizedKeys = [
              # "ssh-ed25519 AAAA... you@host"
            ];
            docker.enable = false;
          };
          networking.hostName = "local-vm";
          networking.hostId = "deadc0de";  # replace with your own
          users.mutableUsers = false;
          users.users.admin.initialPassword = "changeme";
          users.users.root.initialPassword = "changeme";
          security.sudo.wheelNeedsPassword = false;
          time.timeZone = "UTC";
          i18n.defaultLocale = "fr_FR.UTF-8";
          console.keyMap = "fr";
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

:::caution[Change the passwords]
`initialPassword = "changeme"` ships with `mutableUsers = false`, so the password
can never be changed with `passwd` — it stays `changeme`. Replace it with a real
`hashedPassword` (e.g. `mkpasswd -m sha-512`) before building anything but a
throwaway VM. The build emits warnings while these placeholders are still in place.
:::

## See Also

- [cogitator-sarcophagus-kvm](/stc/en/cogitator/sarcophagus-kvm/) — full options reference for the image builder
- [relics-impermanence](/stc/en/relics/impermanence/) — how the rollback works
- [cogitator-vm](/stc/en/cogitator/vm/) — the VM base profile options
