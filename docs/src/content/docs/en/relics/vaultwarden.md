---
title: Vaultwarden
description: Alternative Bitwarden server — self-hosted password manager, automatic TLS, WebSocket support.
---

**Module :** `stc.nixosModules.relics-vaultwarden`

Runs Vaultwarden, a Bitwarden-compatible server written in Rust, as a NixOS service. Automatically synchronizes with Traefik if enabled. Persists data to `/persist` and supports periodic backups. Enables automatic registration and can restrict signups to specific email domains.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.vaultwarden.enable` | bool | `false` | Enable Vaultwarden server. |
| `stc.vaultwarden.hostname` | string | — | Public domain name (used for Traefik route). **Required.** |
| `stc.vaultwarden.backup` | bool | `false` | Enable periodic backups to `/var/backup/vaultwarden`. |
| `stc.vaultwarden.signupsDomains` | list[string] | `[]` | Restrict signups to these email domains. Empty list = all domains accepted. |
| `stc.vaultwarden.showPasswordHint` | bool | `false` | Show password hints on the login page. Disabled by default for security. |

## What it does

- **Vaultwarden service :** Self-hosted password manager, compatible with Bitwarden clients
- **Localhost only :** Listens on `127.0.0.1:8222` (never exposed directly)
- **Traefik integration :** Automatically creates HTTPS route if `relics-traefik` is enabled
- **WebSocket :** Enables real-time synchronization between devices
- **Persistence :** Saves data to `/persist` — **requires `relics-impermanence`**
- **Optional backups :** Periodic backups to `/var/backup/vaultwarden` if `backup = true`
- **Signup restriction :** Optional — limit new accounts to specific domains
- **Invitations :** Enables invitations (invitation-based registration)

## Example usage (with Traefik)

```nix
modules = [
  stc.nixosModules.relics-impermanence
  stc.nixosModules.relics-traefik
  stc.nixosModules.relics-vaultwarden
];

{
  stc.impermanence.enable = true;
  stc.traefik = {
    enable = true;
    email = "admin@example.com";
  };
  stc.vaultwarden = {
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
  stc.impermanence.enable = true;
  stc.vaultwarden = {
    enable = true;
    hostname = "localhost";  # or local IP
  };
}
```

## Combine with

- **[relics-impermanence](/en/relics/impermanence)** (required) — Persists Vaultwarden data
- **[relics-traefik](/en/relics/traefik)** (recommended) — Automatically integrates for TLS and public domain

## Notes

- Bitwarden clients (mobile, desktop, web) connect directly to Vaultwarden as if it were the official Bitwarden server
- Data is encrypted client-side — the server never sees passwords in cleartext
- ACME certificates are managed by Traefik (if enabled) — Vaultwarden doesn't handle them
