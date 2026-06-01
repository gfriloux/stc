---
title: Hardening Profile
description: cogitator-hardening — enable all four hardening relics with a single option.
---

**Module:** `stc.nixosModules.cogitator-hardening`

One option to harden them all. Activates kernel, network, filesystem, and SSH
hardening in a single toggle. For surgical control, use the individual relics
instead and enable them independently.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.hardening.enable` | bool | `false` | Enable the full hardening suite (kernel + network + filesystem + SSH) |

## What It Composes

Enabling `stc.hardening.enable = true` is equivalent to setting all four of these:

```nix
stc.hardening.kernel.enable = true;
stc.hardening.network.enable = true;
stc.hardening.filesystem.enable = true;
stc.hardening.ssh.enable = true;
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
  stc.hardening.enable = true;

  # Open additional ports beyond SSH (22)
  stc.hardening.network.allowedTCPPorts = [ 22 80 443 ];

  # Increase /tmp size on memory-rich machines
  stc.hardening.filesystem.tmpSize = "4G";
}
```

## See Also

- [Hardening relics](/stc/en/relics/hardening/) — detailed documentation of each individual relic
