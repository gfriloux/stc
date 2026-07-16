# STC — Standard Template Construct

A Nix flake library of reusable NixOS and Home Manager modules.  
Themed after the Adeptus Mechanicus. Functional in all universes.

> *Praise the Omnissiah. May your modules evaluate without heresy.*

**Documentation:** https://gfriloux.github.io/stc

---

## Overview

STC is a **library only** — it contains no system configuration. Your production flake imports the modules it needs and configures them.

The library is organised into four layers:

| Layer | Path | Purpose |
|-------|------|---------|
| **Relics** | `relics/` | Atomic NixOS + Home Manager modules |
| **Cogitators** | `cogitator/` | Curated profiles — composed from relics |
| **Forge** | `forge/` | Disk layouts, image builders, devShell templates, CI purity seals |
| **Rites** | `rites/` | Shared lib helpers |

---

## Namespace

All options live under `stc.*`:

```
stc.relics.*       — individual module options  (stc.relics.boot, stc.relics.zfs, …)
stc.cogitator.*    — profile options            (stc.cogitator.vm, stc.cogitator.hardening, …)
```

---

## Quick start

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    stc = {
      url = "github:gfriloux/stc";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, stc, ... }: {
    nixosConfigurations.my-machine = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        stc.nixosModules.relics-boot
        stc.nixosModules.relics-zfs
        stc.nixosModules.cogitator-hardening

        ({ ... }: {
          stc.relics.boot.enable = true;
          stc.relics.zfs.enable = true;
          stc.cogitator.hardening.enable = true;
        })
      ];
    };
  };
}
```

See the `schematics/` directory for complete working examples:
- `schematics/local-vm/` — QEMU/KVM VM with ZFS + impermanence + hardening
- `schematics/aws-ami/` — AWS EC2 AMI with ZFS + impermanence + AWS platform
- `schematics/dreadnought/` — Running EC2 instance profile

---

## Available modules

### nixosModules (relics)

| Module | Option | Description |
|--------|--------|-------------|
| `relics-boot` | `stc.relics.boot` | systemd-boot + EFI |
| `relics-zfs` | `stc.relics.zfs` | ZFS kernel, scrub, TRIM, ZED, snapshots |
| `relics-networking` | `stc.relics.networking` | DHCP + Quad9 DNS |
| `relics-impermanence` | `stc.relics.impermanence` | ZFS rollback at every boot |
| `relics-aws` | `stc.relics.aws` | EC2 drivers, NTP, serial console, EBS grow |
| `relics-traefik` | `stc.relics.traefik` | Traefik native NixOS service + Let's Encrypt |
| `relics-vaultwarden` | `stc.relics.vaultwarden` | Vaultwarden + auto Traefik route |
| `relics-amd-gpu` | `stc.relics.amdGpu` | AMD GPU drivers, VDPAU/VAAPI, 32-bit |
| `relics-pipewire` | `stc.relics.pipewire` | Pipewire + RTKit + ALSA 32-bit |
| `relics-plasma6` | `stc.relics.plasma6` | KDE Plasma 6 + SDDM + Wayland |
| `relics-yubikey-system` | `stc.relics.yubikey` | pcscd + udev rules |
| `relics-hardening-kernel` | `stc.relics.hardening.kernel` | sysctl kernel hardening |
| `relics-hardening-network` | `stc.relics.hardening.network` | sysctl network hardening |
| `relics-hardening-filesystem` | `stc.relics.hardening.filesystem` | /tmp, /proc, /dev/shm hardening |
| `relics-hardening-ssh` | `stc.relics.hardening.ssh` | OpenSSH hardened config |
| `relics-docker-traefik` | `stc.relics.docker.traefik` | Traefik v3 Docker container |
| `relics-docker-socket-proxy` | `stc.relics.docker.socketProxy` | Filtering proxy in front of the Docker socket |
| `relics-docker-crowdsec` | `stc.relics.docker.crowdsec` | CrowdSec IDS/IPS Docker container |
| `relics-docker-notify` | `stc.relics.docker.notify` | ntfy failure notifications for Docker |

### nixosModules (cogitators)

| Module | Option | Description |
|--------|--------|-------------|
| `cogitator-hardening` | `stc.cogitator.hardening` | Full hardening suite (all 4 hardening relics) |
| `cogitator-vm` | `stc.cogitator.vm` | Base VM: fish, SSH, user, Docker, Nix GC |
| `cogitator-docker-server` | `stc.cogitator.docker-server` | Traefik + socket-proxy + CrowdSec + ntfy Docker stack |
| `cogitator-plasma` | `stc.cogitator.plasma` | KDE Plasma 6 + Pipewire |
| `cogitator-gaming` | `stc.cogitator.gaming` | AMD GPU + Pipewire + Steam |
| `cogitator-sarcophagus-kvm` | `stc.cogitator.sarcophagus-kvm` | QEMU/KVM disk image builder |
| `cogitator-sarcophagus-aws` | `stc.cogitator.sarcophagus-aws` | AWS AMI disk image builder |
| `cogitator-dreadnought` | `stc.cogitator.dreadnought` | Running EC2 instance profile |

### homeModules (relics)

| Module | Option | Description |
|--------|--------|-------------|
| `relics-kitty` | `stc.relics.gui.kitty` | Kitty terminal + Nerd Fonts |
| `relics-ghostty` | `stc.relics.gui.ghostty` | Ghostty terminal |
| `relics-zen-browser` | `stc.relics.gui.zen-browser` | Zen Browser |
| `relics-plasma-manager` | `stc.relics.plasmaManager` | Declarative KDE config via plasma-manager |
| `relics-yubikey-user` | `stc.relics.yubikey` | YubiKey tools + touch detector |

### homeModules (cogitators)

| Module | Option | Description |
|--------|--------|-------------|
| `cogitator-enginseer` | `stc.cogitator.enginseer` | Full CLI toolkit (fish, gitflow, catppuccin, television) |
| `cogitator-desktop` | `stc.cogitator.desktop` | GUI apps: Kitty, Zen Browser |

---

## Development

```bash
# Nix tools (alejandra, statix, deadnix)
nix develop

# Documentation (Node.js + Astro)
nix develop .#docs
cd docs && npm install && npm run dev

# Format + lint + check
just ci
```

---

## Releases

STC follows [Semantic Versioning](https://semver.org/) and is pre-1.0 (`0.x`).
See [`CHANGELOG.md`](./CHANGELOG.md) for the release history and
[`.claude/plans/README.md`](./.claude/plans/README.md) for the map of tags to the
work that produced them. The changelog is generated from Conventional Commits with
`just changelog` (git-cliff).

---

## Migrating to `stc.relics.*`

If your configuration uses the flat `stc.boot`, `stc.zfs`, `stc.traefik`, etc.
(the layout before `v0.2.0`), the old namespace still works but emits a
deprecation warning. Migrate to the canonical `stc.relics.*` / `stc.cogitator.*`
namespaces — see [`MIGRATION.md`](./MIGRATION.md). The legacy aliases will be
removed at the next major release (`v1.0.0`).

---

## Security

Options that accept secrets use a `*File` suffix and read the file at runtime —
STC never stores secret values inline, and is agnostic to the secrets backend
(sops-nix, agenix, plain files).
