---
title: Networking
description: Base networking configuration — DHCP on all interfaces, Quad9 DNS by default.
---

**Module:** `stc.nixosModules.relics-networking`

Sensible networking defaults. DHCP on all interfaces, Quad9 DNS.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.networking.enable` | bool | `false` | Enable base networking configuration |
| `stc.relics.networking.domain` | `null \| string` | `null` | DNS search domain. `null` means no domain is set |
| `stc.relics.networking.nameservers` | list of strings | `[ "9.9.9.9" "149.112.112.112" ]` | DNS resolvers |
| `stc.relics.networking.dhcp` | bool | `true` | Use DHCP on all interfaces. Set `false` to declare interfaces yourself |

## What It Does

When enabled:

- Sets `networking.usePredictableInterfaceNames = true` (mkDefault — overridable)
- Sets `networking.useDHCP` from `dhcp` (an option, not a `mkDefault` — see below)
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
  stc.relics.networking.enable = true;

  # Optional overrides
  stc.relics.networking.domain = "corp.example.com";
  stc.relics.networking.nameservers = [ "192.168.1.1" ];

  # NixOS-level: set the hostname and ZFS hostId here
  networking.hostName = "my-server";
  networking.hostId = "a1b2c3d4";
}
```

:::tip[Per-interface DHCP]
Set `stc.relics.networking.dhcp = false` and declare each interface explicitly.

Since `v0.18.0` this is an **option** rather than a `lib.mkDefault` on
`networking.useDHCP`, because the seal added in that release measured a real
collision: `networking.ifstate` also writes that option with `mkDefault`, with
the opposite value, and two disagreeing defaults are a build error. On the
previous release this relic plus `networking.ifstate.enable = true` failed with
`has conflicting definition values` and no clean way out. Now it either builds —
with `dhcp = false` — or fails on ifstate's own assertion, which says what to do
and links to the upstream issue.
:::

## Not a relic: time synchronisation

There is no `relics.networking.ntp`, and the absence is deliberate. NixOS
already enables `systemd-timesyncd` by default — measured `true` on a bare node
and on all three schematics, with no STC line involved — and upstream already
exposes `services.timesyncd.servers` for the authoritative source. A relic would
alias options nixpkgs provides.

One point is worth knowing before you set a time server: `networking.timeServers`
writes `FallbackNTP=`, the **lowest-priority** field, not the authoritative
`NTP=`. Use `services.timesyncd.servers` when you mean *"synchronise from this
host"*. The full measurement, including why the AWS relic deliberately uses the
fallback, is in
[ANSSI-BP-028 fidelity](/stc/en/reference/anssi-bp-028/).
