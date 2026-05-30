---
title: Networking
description: Base networking configuration — DHCP on all interfaces, Quad9 DNS by default.
---

**Module:** `stc.nixosModules.relics-networking`

Sensible networking defaults. DHCP on all interfaces, Quad9 DNS.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.networking.enable` | bool | `false` | Enable base networking configuration |
| `stc.networking.domain` | `null \| string` | `null` | DNS search domain. `null` means no domain is set |
| `stc.networking.nameservers` | list of strings | `[ "9.9.9.9" "149.112.112.112" ]` | DNS resolvers |

## What It Does

When enabled:

- Sets `networking.usePredictableInterfaceNames = true` (mkDefault — overridable)
- Sets `networking.useDHCP = true` (mkDefault — override per interface if needed)
- Applies `nameservers` to `networking.nameservers`
- Applies `domain` to `networking.domain` when it is not null

## Why Quad9?

Quad9 (`9.9.9.9` / `149.112.112.112`) is the default for three reasons:

1. **Privacy** — no query logging, no data selling
2. **Security** — blocks known malicious domains using threat intelligence feeds
3. **DNSSEC** — validates DNS responses, prevents spoofing

Change `nameservers` if your threat model differs, your organisation runs an
internal resolver, or you operate in a jurisdiction where Quad9 is blocked.

## Usage Example

```nix
# flake.nix
modules = [
  stc.nixosModules.relics-networking
  ./configuration.nix
];

# configuration.nix
{
  stc.networking.enable = true;

  # Optional overrides
  stc.networking.domain = "corp.example.com";
  stc.networking.nameservers = [ "192.168.1.1" ];

  # NixOS-level: set the hostname and ZFS hostId here
  networking.hostName = "my-server";
  networking.hostId = "a1b2c3d4";
}
```

:::tip[Per-interface DHCP]
`useDHCP` is set with `mkDefault`. To disable DHCP globally and configure
interfaces individually, set `networking.useDHCP = false` in your configuration
and then declare each interface explicitly.
:::
