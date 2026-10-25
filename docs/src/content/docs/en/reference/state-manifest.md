---
title: State manifest
description: Where STC's relics keep persistent state, what it is, and how to read the list for your host.
---

**Module:** `stc.nixosModules.relics-state` (every relic below imports it)

Some relics create persistent state: certificates, databases, keys. Each one
records what it creates in `stc.relics.state.paths`, so you can see the full
list for a host without reading relic source:

```bash
nix eval --json .#nixosConfigurations.<host>.config.stc.relics.state.paths | jq
```

```json
[
  {
    "path": "/srv/docker/crowdsec/data",
    "type": "directory",
    "description": "CrowdSec's local API database: decisions (active bans), alerts and machine registrations.",
    "kind": "data"
  }
]
```

An entry appears only when its relic is enabled. Its path comes from the
relic's options (`dataDir`, `services.openssh.hostKeys`, Vaultwarden's
`StateDirectory`), so a path you moved shows up where you moved it. `type` says
whether it is a `file` or a `directory`.

:::caution[Descriptive only]
Nothing in STC reads this list. It does not back anything up, and it does not
persist anything under [impermanence](/stc/en/relics/impermanence/). It tells
you **what exists**. Your backup job and your
`stc.relics.impermanence.extraDirectories` still have to act on it.
:::

## Kinds

| `kind` | Meaning | Backup |
|---|---|---|
| `data` | Lost means lost | Back it up |
| `credentials` | Keys and secrets | Back them up, encrypted apart from ordinary data |
| `cache` | Rebuilt on its own | Not needed |
| `log` | History, not state | Keep as long as you need it |

## What each relic declares

| Relic | Path | Type | Kind |
|---|---|---|---|
| `relics-docker-traefik` | `<dataDir>/acme.json` | file | credentials |
| `relics-docker-traefik` | `<dataDir>/logs` | directory | log |
| `relics-docker-traefik` | `<dataDir>/conf/traefik_dynamic.yml` (when `dynamicConfigFile` is unset: you write it by hand) | file | data |
| `relics-docker-crowdsec` | `<dataDir>/data` | directory | data |
| `relics-docker-crowdsec` | `<dataDir>/etc` | directory | credentials |
| `relics-traefik` | `services.traefik.dataDir` (`/var/lib/traefik`) | directory | credentials |
| `relics-vaultwarden` | `/var/lib/vaultwarden` (`/var/lib/bitwarden_rs` with a `stateVersion` before 24.11) | directory | data |
| `relics-vaultwarden` | `/var/backup/vaultwarden` (with `backup = true`) | directory | data |
| `relics-hardening-ssh` | each `services.openssh.hostKeys` path | file | credentials |
| `relics-zfs` | `/var/log/zed.debug.log` | file | log |

Vaultwarden's directory is listed as `data`, but it also holds `rsa_key.pem`,
the key that signs login tokens. If you encrypt credentials apart, include it.

The other NixOS relics create no persistent state worth restoring. Home Manager
relics are out of scope: they live in a different module system. The one with
real state there is zen-browser's profile (`~/.zen`).

The list covers state that **relics** create. The docker-server profile enables
Docker itself, and `/var/lib/docker` holds your own images and volumes, so it
is not declared here: what to keep in it depends on your applications.

## Feeding impermanence

Some entries are already persisted when impermanence is on, and listing them a
second time makes impermanence refuse to evaluate (it asserts on duplicates):

- the native Traefik and Vaultwarden relics persist their own directories;
- the impermanence relic persists `/var/log` (so the ZED log) and the default
  SSH host keys.

What is left is mostly the Docker relics' `dataDir` (`/srv/docker/…` by
default). Put it on a persistent dataset, or list the entries yourself,
directories and files apart:

```bash
m=$(nix eval --json .#nixosConfigurations.<host>.config.stc.relics.state.paths)
echo "$m" | jq -r '.[] | select(.path | startswith("/srv/docker/")) | select(.type == "directory") | .path'  # extraDirectories
echo "$m" | jq -r '.[] | select(.path | startswith("/srv/docker/")) | select(.type == "file") | .path'       # extraFiles
```

## Proving

- `provings/docker-server.nix` checks that every path in the manifest exists on
  the booted host, and that a node without CrowdSec lists none of its paths.
  The hand-written `traefik_dynamic.yml` must be listed, but nothing creates it
  on a fresh node.
- `provings/hardening.nix` checks that the host keys in the manifest are exactly
  the ones `sshd -T` loads.
