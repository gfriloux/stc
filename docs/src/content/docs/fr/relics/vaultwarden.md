---
title: Vaultwarden
description: Serveur Bitwarden alternatif — gestionnaire de mots de passe self-hosted, TLS auto, WebSocket.
---

**Module :** `stc.nixosModules.relics-vaultwarden`

Lance Vaultwarden, un serveur Bitwarden-compatible écrit en Rust, comme service NixOS. Se synchronise automatiquement avec Traefik si activé. Persiste les données sur `/persist` et supporte les backups périodiques. Les inscriptions et invitations sont désactivées par défaut.

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.relics.vaultwarden.enable` | bool | `false` | Active le serveur Vaultwarden. |
| `stc.relics.vaultwarden.hostname` | string | — | Nom de domaine public (utilisé pour la route Traefik). **Requis.** |
| `stc.relics.vaultwarden.backup` | bool | `false` | Active les backups périodiques vers `/var/backup/vaultwarden`. |
| `stc.relics.vaultwarden.signupsAllowed` | bool | `false` | Autorise l'auto-inscription des nouveaux utilisateurs. Désactivé par défaut. |
| `stc.relics.vaultwarden.invitationsAllowed` | bool | `false` | Autorise les invitations d'organisation. Désactivé par défaut. |
| `stc.relics.vaultwarden.signupsDomains` | list[string] | `[]` | Limiter les inscriptions à ces domaines email. N'a d'effet que si `signupsAllowed = true`. |
| `stc.relics.vaultwarden.showPasswordHint` | bool | `false` | Affiche les indices de mot de passe sur la page de connexion. Désactivé par défaut pour la sécurité. |

## Ce qu'il fait

- **Service Vaultwarden :** Gestionnaire de mots de passe self-hosted, compatible avec les clients Bitwarden
- **Localhost uniquement :** Écoute sur `127.0.0.1:8222` (jamais exposé directement)
- **Intégration Traefik :** Crée automatiquement la route HTTPS si `relics-traefik` est activé
- **Domaine :** `DOMAIN` est défini automatiquement à `https://${hostname}`. Indispensable pour que WebAuthn/passkeys, les pièces jointes et les liens d'invitation fonctionnent derrière le proxy
- **WebSocket :** la synchro temps réel est servie automatiquement sur le port principal (Vaultwarden ≥ 1.29 — l'ancien flag `WEBSOCKET_ENABLED` n'est plus nécessaire)
- **Persistence :** sur les systèmes impermanence, persiste `/var/lib/vaultwarden` (et le répertoire de backup) via `relics-impermanence` quand il est activé, en suivant son `persistPath`. S'évalue sans souci sans impermanence — le bloc de persistence est alors simplement omis.
- **Backups optionnels :** Backups périodiques vers `/var/backup/vaultwarden` si `backup = true`
- **Inscriptions :** Désactivées par défaut — passer `signupsAllowed = true` pour ouvrir
- **Invitations :** Désactivées par défaut — passer `invitationsAllowed = true` pour autoriser
- **Restriction d'inscriptions :** Optionnel — limiter les nouveaux comptes à des domaines spécifiques via `signupsDomains`

## Exemple d'utilisation (avec Traefik)

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
    # signupsDomains = [ "example.com" ];  # optionnel : restreindre
  };
}
```

Sans Traefik (localhost uniquement) :

```nix
modules = [
  stc.nixosModules.relics-impermanence
  stc.nixosModules.relics-vaultwarden
];

{
  stc.relics.impermanence.enable = true;
  stc.relics.vaultwarden = {
    enable = true;
    hostname = "localhost";  # ou IP locale
  };
}
```

## À combiner avec

- **[relics-impermanence](/stc/fr/relics/impermanence)** (recommandé sur les systèmes impermanence) — Persiste les données Vaultwarden
- **[relics-traefik](/stc/fr/relics/traefik)** (recommandé) — S'intègre automatiquement pour TLS et domaine public

## Notes

- Les clients Bitwarden (mobile, desktop, web) se connectent directement à Vaultwarden comme si c'était le serveur Bitwarden officiel
- Les données sont chiffrées côté client — le serveur ne voit jamais les mots de passe en clair
- Les certificats ACME sont gérés par Traefik (si activé) — Vaultwarden ne s'en occupe pas
