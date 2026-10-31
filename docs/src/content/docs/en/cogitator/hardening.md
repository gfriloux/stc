---
title: Hardening Profile
description: cogitator-hardening — enable all seven hardening relics with a single option.
---

**Module:** `stc.nixosModules.cogitator-hardening`

One option to harden them all. Activates kernel, network, filesystem, SSH,
module-blacklist, scheduler-access and audit hardening in a single toggle. For surgical control, use the
individual relics instead and enable them independently.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.cogitator.hardening.enable` | bool | `false` | Enable the full hardening suite (kernel + network + filesystem + SSH + module blacklist + scheduler access + audit) |

## What It Composes

Enabling `stc.cogitator.hardening.enable = true` is equivalent to setting all seven of these:

```nix
stc.relics.hardening.kernel.enable = true;
stc.relics.hardening.network.enable = true;
stc.relics.hardening.filesystem.enable = true;
stc.relics.hardening.ssh.enable = true;
stc.relics.hardening.modules.enable = true;
stc.relics.hardening.scheduler.enable = true;
stc.relics.hardening.audit.enable = true;
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

## Taking the suite minus a part

Since `v0.18.0` the sub-relics are enabled with `lib.mkDefault`, so you can
keep the single toggle and still decline one of them:

```nix
stc.cogitator.hardening.enable = true;

# You own your sshd configuration, or you manage cron policy yourself.
stc.relics.hardening.ssh.enable = false;
```

Before `v0.18.0` this needed `lib.mkForce`, or giving up this profile entirely
and importing the relics à la carte. See
[Overridable defaults](/stc/en/reference/overridable-defaults/) for the rule and
the full list.

## See Also

- [Hardening relics](/stc/en/relics/hardening/) — detailed documentation of each individual relic
- [Overridable defaults](/stc/en/reference/overridable-defaults/) — what this profile pins and what it only proposes
