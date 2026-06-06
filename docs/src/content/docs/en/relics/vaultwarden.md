---
title: Vaultwarden
description: Alternative Bitwarden server — self-hosted password manager, automatic TLS, WebSocket support.
---

**Module :** `stc.nixosModules.relics-vaultwarden`

Runs Vaultwarden, a Bitwarden-compatible server written in Rust, as a NixOS service. Automatically synchronizes with Traefik if enabled. Persists data to `/persist` and supports periodic backups. Signups and invitations are disabled by default.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.vaultwarden.enable` | bool | `false` | Enable Vaultwarden server. |
| `stc.relics.vaultwarden.hostname` | string | — | Public domain name (used for Traefik route). **Required.** |
| `stc.relics.vaultwarden.backup` | bool | `false` | Enable periodic backups to `/var/backup/vaultwarden`. |
| `stc.relics.vaultwarden.signupsAllowed` | bool | `false` | Allow new user self-registration. Disabled by default. |
| `stc.relics.vaultwarden.invitationsAllowed` | bool | `false` | Allow organization invitations. Disabled by default. |
| `stc.relics.vaultwarden.signupsDomains` | list[string] | `[]` | Restrict signups to these email domains. Only applies when `signupsAllowed = true`. |
| `stc.relics.vaultwarden.showPasswordHint` | bool | `false` | Show password hints on the login page. Disabled by default for security. |

## What it does

- **Vaultwarden service :** Self-hosted password manager, compatible with Bitwarden clients
- **Localhost only :** Listens on `127.0.0.1:8222` (never exposed directly)
- **Traefik integration :** Automatically creates HTTPS route if `relics-traefik` is enabled
- **WebSocket :** real-time sync is served on the main port automatically (Vaultwarden ≥ 1.29 — the old `WEBSOCKET_ENABLED` flag is no longer needed)
- **Persistence :** on impermanence systems, persists `/var/lib/vaultwarden` (and the backup dir) through `relics-impermanence` when it is enabled, following its `persistPath`. Evaluates fine without impermanence — the persistence block is simply omitted.
- **Optional backups :** Periodic backups to `/var/backup/vaultwarden` if `backup = true`
- **Signups :** Disabled by default — set `signupsAllowed = true` to allow registration
- **Invitations :** Disabled by default — set `invitationsAllowed = true` to allow org invitations
- **Signup restriction :** Optional — limit new accounts to specific domains via `signupsDomains`

## Example usage (with Traefik)

```nix
modules = [
  stc.nixosModules.relics-impermanence
  stc.nixosModules.relics-traefik
  stc.nixosModules.relics-vaultwarden
];

{
  stc.relics.impermanence.enable = true;
  stc.relics.traefik = {
    enable = true;
    email = "admin@example.com";
  };
  stc.relics.vaultwarden = {
    enable = true;
    hostname = "vault.example.com";
    backup = true;
    # signupsDomains = [ "example.com" ];  # optional: restrict signups
  };
}
```

Without Traefik (localhost only) :

```nix
modules = [
  stc.nixosModules.relics-impermanence
  stc.nixosModules.relics-vaultwarden
];

{
  stc.relics.impermanence.enable = true;
  stc.relics.vaultwarden = {
    enable = true;
    hostname = "localhost";  # or local IP
  };
}
```

## Combine with

- **[relics-impermanence](/stc/en/relics/impermanence)** (recommended on impermanence systems) — Persists Vaultwarden data
- **[relics-traefik](/stc/en/relics/traefik)** (recommended) — Automatically integrates for TLS and public domain

## Notes

- Bitwarden clients (mobile, desktop, web) connect directly to Vaultwarden as if it were the official Bitwarden server
- Data is encrypted client-side — the server never sees passwords in cleartext
- ACME certificates are managed by Traefik (if enabled) — Vaultwarden doesn't handle them
