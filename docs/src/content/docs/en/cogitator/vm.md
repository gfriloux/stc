---
title: VM Profile
description: cogitator-vm — opinionated base for NixOS development and staging VMs.
---

**Module:** `stc.nixosModules.cogitator-vm`

An opinionated base for a NixOS development or staging virtual machine: fish shell,
SSH, a primary user with wheel access, optional Docker, and automatic Nix GC to
keep store bloat under control.

Compose with `cogitator-hardening` and `cogitator-enginseer` for a complete
developer VM.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.cogitator.vm.enable` | bool | `false` | Enable the STC base VM profile |
| `stc.cogitator.vm.username` | string | `"admin"` | Primary user account created on the VM |
| `stc.cogitator.vm.authorizedKeys` | list of strings | `[]` | SSH authorized keys for the primary user |
| `stc.cogitator.vm.docker.enable` | bool | `true` | Enable Docker and add the primary user to the docker group |
| `stc.cogitator.vm.nix.gc.enable` | bool | `true` | Enable automatic Nix garbage collection |
| `stc.cogitator.vm.nix.gc.dates` | string | `"weekly"` | When to run Nix GC (systemd calendar expression) |
| `stc.cogitator.vm.nix.gc.keepDays` | int | `5` | Delete Nix store paths older than this many days |

## What It Does

When enabled:

- Enables `nix-command` and `flakes` experimental features
- Enables `nix.optimise.automatic` (deduplication)
- Configures Nix GC if `nix.gc.enable = true`
- Enables `programs.fish`
- Creates a user (`username`) with:
  - `isNormalUser = true`
  - `extraGroups = [ "wheel" ]` (+ `"docker"` if `docker.enable = true`)
  - `shell = pkgs.fish`
  - `linger = true`
  - SSH authorized keys from `authorizedKeys`
- Enables `services.openssh`
- If `docker.enable = true`: enables `virtualisation.docker` and installs `docker-compose`

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
    nix.gc = {
      enable = true;
      dates = "weekly";
      keepDays = 7;
    };
  };

  stc.hardening.enable = true;
  stc.hardening.network.allowedTCPPorts = [ 22 ];

  networking.hostName = "dev-vm";
  networking.hostId = "a1b2c3d4";

  system.stateVersion = "24.11";
}
```

## See Also

- [cogitator-hardening](/stc/en/cogitator/hardening/) — pair with this for a hardened VM
- [cogitator-enginseer](/stc/en/cogitator/enginseer/) — pair with this for the full CLI toolkit
- [Schematic: local-vm](/stc/en/schematics/local-vm/) — complete working example
