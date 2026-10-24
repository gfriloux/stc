---
title: VM Profile
description: cogitator-vm — opinionated base for NixOS development and staging VMs.
---

**Module:** `stc.nixosModules.cogitator-vm`

An opinionated base for a NixOS development or staging virtual machine: fish shell,
SSH, a primary user with wheel access, optional Docker, and a bounded Nix store
and journal through [Nix Housekeeping](/stc/en/relics/nix-housekeeping/), with
a 5-day GC window.

Compose with `cogitator-hardening` and `cogitator-enginseer` for a complete
developer VM.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.cogitator.vm.enable` | bool | `false` | Enable the STC base VM profile |
| `stc.cogitator.vm.username` | string | `"admin"` | Primary user account created on the VM |
| `stc.cogitator.vm.authorizedKeys` | list of strings | `[]` | SSH authorized keys for the primary user |
| `stc.cogitator.vm.linger` | bool | `true` | Keep the user's systemd instance/services running without an open session. Set `false` on hardened hosts. |
| `stc.cogitator.vm.docker.enable` | bool | `false` | Enable Docker and add the primary user to the docker group (≈ root — opt-in) |

## What It Does

When enabled:

- Enables `nix-command` and `flakes` experimental features
- Enables [Nix Housekeeping](/stc/en/relics/nix-housekeeping/) (`mkDefault`) with
  `gc.keepDays = 5` (`mkDefault`): weekly GC, GC under disk pressure, weekly
  deduplication, builds that yield, journal cap
- Enables `programs.fish`
- Creates a user (`username`) with:
  - `isNormalUser = true`
  - `extraGroups = [ "wheel" ]` (+ `"docker"` if `docker.enable = true`)
  - `shell = pkgs.fish`
  - `linger = cfg.linger` (defaults to `true`)
  - SSH authorized keys from `authorizedKeys`
- Enables `services.openssh`
- If `docker.enable = true`: enables `virtualisation.docker` and installs `docker-compose`

:::caution[docker group ≈ root, and sudo with key-only SSH]
`docker.enable` is off by default: adding the user to the `docker` group is
equivalent to root access, so it is opt-in rather than a silent default.

The user is created with key-only SSH and **no password**, so `sudo` is
unusable as-is. If you need `sudo`, set `security.sudo.wheelNeedsPassword = false`
(passwordless — convenient for an SSH-key-only box, but understand the
trade-off) or assign the user a password out of band.

`linger = true` is set so user services (and rootless workloads) keep running
when the user is not logged in.
:::

:::note[Renamed in v0.19.0: the GC options]
`stc.cogitator.vm.nix.gc.{enable,dates,keepDays}` moved to
`stc.relics.nixHousekeeping.gc.{enable,dates,keepDays}`. The old names still
work and emit a deprecation warning; a value set there still beats the
profile's 5-day default.

The profile now also gets the rest of the relic: `min-free` / `max-free`, a
500M / one-month journal cap, and builds that yield. Each has its own switch
on the relic.
:::

:::note[Breaking change]
`docker.enable` previously defaulted to `true`. If you relied on Docker being
enabled implicitly, set `stc.cogitator.vm.docker.enable = true;` explicitly.
:::

## Usage Example

```nix
# flake.nix
modules = [
  stc.nixosModules.cogitator-vm
  stc.nixosModules.cogitator-hardening
  ./configuration.nix
];

# configuration.nix
{
  stc.cogitator.vm = {
    enable = true;
    username = "alice";
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... alice@laptop"
    ];
    docker.enable = true;
  };
  stc.relics.nixHousekeeping.gc.keepDays = 7;

  stc.cogitator.hardening.enable = true;
  stc.relics.hardening.network.allowedTCPPorts = [ 22 ];

  networking.hostName = "dev-vm";
  networking.hostId = "a1b2c3d4";

  system.stateVersion = "24.11";
}
```

## See Also

- [cogitator-hardening](/stc/en/cogitator/hardening/) — pair with this for a hardened VM
- [cogitator-enginseer](/stc/en/cogitator/enginseer/) — pair with this for the full CLI toolkit
- [Nix Housekeeping](/stc/en/relics/nix-housekeeping/) — the GC and journal options
- [Schematic: local-vm](/stc/en/schematics/local-vm/) — complete working example
