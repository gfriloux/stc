---
title: Traefik
description: Traefik reverse proxy — Automatic Let's Encrypt TLS, HTTP→HTTPS redirect, JSON logs.
---

**Module :** `stc.nixosModules.relics-traefik`

Runs Traefik as a native NixOS service (without Docker). Automatically configures a reverse proxy with Let's Encrypt TLS, HTTP to HTTPS redirection, and structured JSON logging. Certificates are automatically provisioned and renewed.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.traefik.enable` | bool | `false` | Enable Traefik reverse proxy. |
| `stc.relics.traefik.email` | string | — | Email address for Let's Encrypt ACME registration. **Required.** |
| `stc.relics.traefik.logLevel` | string | `"INFO"` | Log level: `DEBUG`, `INFO`, `WARN`, or `ERROR`. |

## What it does

- **Native reverse proxy :** NixOS Traefik service (no Docker)
- **Port 80 :** Automatically redirects to HTTPS
- **Port 443 :** TLS with Let's Encrypt certificates, HTTP-01 challenge
- **JSON logs :** Traefik and access logs in JSON format in `/var/lib/traefik/`
- **Header redaction :** the access log drops request headers by default and only keeps non-sensitive diagnostic ones (`User-Agent`, `X-Real-Ip`, `X-Forwarded-For`, `X-Forwarded-Proto`). `Authorization` and `Cookie` are never written, even though the log is persisted.
- **Firewall :** Automatically opens ports 80 and 443
- **Persistence :** on impermanence systems, persists `/var/lib/traefik` (ACME certs) through `relics-impermanence` when it is enabled, following its `persistPath`. Evaluates fine without impermanence — the persistence block is simply omitted.

## Example usage

```nix
modules = [
  stc.nixosModules.relics-impermanence
  stc.nixosModules.relics-traefik
];

{
  stc.relics.impermanence.enable = true;
  stc.relics.traefik = {
    enable = true;
    email = "admin@example.com";
  };
}
```

Traefik listens on `localhost:8080` for the API/dashboard. For a backend service, use Traefik dynamic routes (see `relics-vaultwarden` for an example of automatic integration).

## Combine with

- **[relics-impermanence](/stc/en/relics/impermanence)** (recommended on impermanence systems) — Persists ACME certificates
- **[relics-vaultwarden](/stc/en/relics/vaultwarden)** — Automatically integrates with Traefik
- **Other NixOS services** — Traefik can route any HTTP service (Nextcloud, Gitea, etc.)

## Notes

This relic uses the native NixOS Traefik service. It is distinct from relics-docker-traefik which runs Traefik in Docker. Prefer this relic for a lightweight and declarative setup.
