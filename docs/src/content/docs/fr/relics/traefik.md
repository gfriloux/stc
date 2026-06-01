---
title: Traefik
description: Reverse proxy Traefik — TLS automatique Let's Encrypt, redirection HTTP→HTTPS, logs JSON.
---

**Module :** `stc.nixosModules.relics-traefik`

Lance Traefik comme service NixOS natif (sans Docker). Configure automatiquement un reverse proxy avec TLS Let's Encrypt, redirection HTTP vers HTTPS, et logs structurés en JSON. Les certificats sont automatiquement provisionnés et renouvelés.

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.traefik.enable` | bool | `false` | Active le reverse proxy Traefik. |
| `stc.traefik.email` | string | — | Adresse email pour l'enregistrement ACME Let's Encrypt. **Requis.** |
| `stc.traefik.logLevel` | string | `"INFO"` | Niveau de log : `DEBUG`, `INFO`, `WARN` ou `ERROR`. |

## Ce qu'il fait

- **Reverse proxy natif :** Service NixOS Traefik (pas Docker)
- **Port 80 :** Redirige automatiquement vers HTTPS
- **Port 443 :** TLS avec certificats Let's Encrypt, challenge HTTP-01
- **Logs JSON :** Traefik et accès en JSON dans `/var/lib/traefik/`
- **Firewall :** Ouvre les ports 80 et 443 automatiquement
- **Persistence :** Sauvegarde les certificats ACME sur `/persist` — **nécessite `relics-impermanence`**

## Exemple d'utilisation

```nix
modules = [
  stc.nixosModules.relics-impermanence
  stc.nixosModules.relics-traefik
];

{
  stc.impermanence.enable = true;
  stc.traefik = {
    enable = true;
    email = "admin@example.com";
  };
}
```

Traefik écoute sur `localhost:8080` pour l'API/dashboard. Pour un service backend, utilisez les routes dynamiques Traefik (voir `relics-vaultwarden` pour un exemple d'intégration automatique).

## À combiner avec

- **[relics-impermanence](/stc/fr/relics/impermanence)** (requis) — Persiste les certificats ACME
- **[relics-vaultwarden](/stc/fr/relics/vaultwarden)** — S'intègre automatiquement avec Traefik
- **Autres services NixOS** — Traefik peut router n'importe quel service HTTP (Nextcloud, Gitea, etc.)

## Notes

Ce relic utilise le service NixOS natif de Traefik. Il est distinct de relics-docker-traefik qui exécute Traefik dans Docker. Préférez ce relic pour une installation légère et déclarative.
