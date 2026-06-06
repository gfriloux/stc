---
title: Traefik
description: Reverse proxy Traefik — TLS automatique Let's Encrypt, redirection HTTP→HTTPS, logs JSON.
---

**Module :** `stc.nixosModules.relics-traefik`

Lance Traefik comme service NixOS natif (sans Docker). Configure automatiquement un reverse proxy avec TLS Let's Encrypt, redirection HTTP vers HTTPS, et logs structurés en JSON. Les certificats sont automatiquement provisionnés et renouvelés.

:::note
STC fournit **deux déploiements Traefik indépendants** : celui-ci, natif, et un conteneur Docker (`relics-docker-traefik`, voir la [pile Docker](/fr/relics/docker/)). Choisis-en un par hôte. Ils diffèrent par leur challenge ACME — le natif utilise HTTP-01, le conteneur TLS-ALPN-01 — mais les deux nomment leur resolver `letsencrypt`, donc les routes de config dynamique référençant `certResolver = "letsencrypt"` sont portables de l'un à l'autre.
:::

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.relics.traefik.enable` | bool | `false` | Active le reverse proxy Traefik. |
| `stc.relics.traefik.email` | string | — | Adresse email pour l'enregistrement ACME Let's Encrypt. **Requis.** |
| `stc.relics.traefik.logLevel` | string | `"INFO"` | Niveau de log : `DEBUG`, `INFO`, `WARN` ou `ERROR`. |

## Ce qu'il fait

- **Reverse proxy natif :** Service NixOS Traefik (pas Docker)
- **Port 80 :** Redirige automatiquement vers HTTPS
- **Port 443 :** TLS avec certificats Let's Encrypt, challenge HTTP-01
- **Logs JSON :** Traefik et accès en JSON dans `/var/lib/traefik/`
- **Masquage des headers :** le log d'accès supprime les headers de requête par défaut et ne conserve que les headers de diagnostic non sensibles (`User-Agent`, `X-Real-Ip`, `X-Forwarded-For`, `X-Forwarded-Proto`). `Authorization` et `Cookie` ne sont jamais écrits, même si le log est persisté.
- **Firewall :** Ouvre les ports 80 et 443 automatiquement
- **Persistence :** sur les systèmes impermanence, persiste `/var/lib/traefik` (certificats ACME) via `relics-impermanence` quand il est activé, en suivant son `persistPath`. S'évalue sans souci sans impermanence — le bloc de persistence est alors simplement omis.

## Exemple d'utilisation

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

Traefik écoute sur `localhost:8080` pour l'API/dashboard. Pour un service backend, utilisez les routes dynamiques Traefik (voir `relics-vaultwarden` pour un exemple d'intégration automatique).

## À combiner avec

- **[relics-impermanence](/stc/fr/relics/impermanence)** (recommandé sur les systèmes impermanence) — Persiste les certificats ACME
- **[relics-vaultwarden](/stc/fr/relics/vaultwarden)** — S'intègre automatiquement avec Traefik
- **Autres services NixOS** — Traefik peut router n'importe quel service HTTP (Nextcloud, Gitea, etc.)

## Notes

Ce relic utilise le service NixOS natif de Traefik. Il est distinct de relics-docker-traefik qui exécute Traefik dans Docker. Préférez ce relic pour une installation légère et déclarative.
