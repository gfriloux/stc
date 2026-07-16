---
title: Hardening Profile
description: cogitator-hardening — enable all five hardening relics with a single option.
---

**Module:** `stc.nixosModules.cogitator-hardening`

One option to harden them all. Activates kernel, network, filesystem, SSH, and
module-blacklist hardening in a single toggle. For surgical control, use the
individual relics instead and enable them independently.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.cogitator.hardening.enable` | bool | `false` | Enable the full hardening suite (kernel + network + filesystem + SSH + module blacklist) |

## What It Composes

Enabling `stc.cogitator.hardening.enable = true` is equivalent to setting all five of these:

```nix
stc.relics.hardening.kernel.enable = true;
stc.relics.hardening.network.enable = true;
stc.relics.hardening.filesystem.enable = true;
stc.relics.hardening.ssh.enable = true;
stc.relics.hardening.modules.enable = true;
```

The individual relic options — `allowedTCPPorts`, `tmpSize`, `allowedTCPForwarding` — remain
fully configurable. The profile only sets the `enable` flags.

## Usage Example

```nix
# flake.nix
modules = [
  stc.nixosModules.cogitator-hardening
  ./configuration.nix
];

# configuration.nix
{
  stc.cogitator.hardening.enable = true;

  # Open additional ports beyond SSH (22)
  stc.relics.hardening.network.allowedTCPPorts = [ 22 80 443 ];

  # Increase /tmp size on memory-rich machines
  stc.relics.hardening.filesystem.tmpSize = "4G";
}
```

## See Also

- [Hardening relics](/stc/en/relics/hardening/) — detailed documentation of each individual relic
