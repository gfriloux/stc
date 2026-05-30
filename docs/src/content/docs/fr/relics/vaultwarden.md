---
title: Vaultwarden
description: Serveur Bitwarden alternatif — gestionnaire de mots de passe self-hosted, TLS auto, WebSocket.
---

**Module :** `stc.nixosModules.relics-vaultwarden`

Lance Vaultwarden, un serveur Bitwarden-compatible écrit en Rust, comme service NixOS. Se synchronise automatiquement avec Traefik si activé. Persiste les données sur `/persist` et supporte les backups périodiques. Permet l'enregistrement automatique et restreint les inscriptions à des domaines email spécifiques.

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.vaultwarden.enable` | bool | `false` | Active le serveur Vaultwarden. |
| `stc.vaultwarden.hostname` | string | — | Nom de domaine public (utilisé pour la route Traefik). **Requis.** |
| `stc.vaultwarden.backup` | bool | `false` | Active les backups périodiques vers `/var/backup/vaultwarden`. |
| `stc.vaultwarden.signupsDomains` | list[string] | `[]` | Limiter les inscriptions à ces domaines email. Liste vide = tous les domaines acceptés. |

## Ce qu'il fait

- **Service Vaultwarden :** Gestionnaire de mots de passe self-hosted, compatible avec les clients Bitwarden
- **Localhost uniquement :** Écoute sur `127.0.0.1:8222` (jamais exposé directement)
- **Intégration Traefik :** Crée automatiquement la route HTTPS si `relics-traefik` est activé
- **WebSocket :** Active les synchronisations en temps réel entre appareils
- **Persistence :** Sauvegarde les données sur `/persist` — **nécessite `relics-impermanence`**
- **Backups optionnels :** Backups périodiques vers `/var/backup/vaultwarden` si `backup = true`
- **Restriction d'inscriptions :** Optionnel — limiter les nouveaux comptes à des domaines spécifiques
- **Invitations :** Permet les invitations (enregistrement par invitation)

## Exemple d'utilisation (avec Traefik)

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
  stc.impermanence.enable = true;
  stc.vaultwarden = {
    enable = true;
    hostname = "localhost";  # ou IP locale
  };
}
```

## À combiner avec

- **[relics-impermanence](/fr/relics/impermanence)** (requis) — Persiste les données Vaultwarden
- **[relics-traefik](/fr/relics/traefik)** (recommandé) — S'intègre automatiquement pour TLS et domaine public

## Notes

- Les clients Bitwarden (mobile, desktop, web) se connectent directement à Vaultwarden comme si c'était le serveur Bitwarden officiel
- Les données sont chiffrées côté client — le serveur ne voit jamais les mots de passe en clair
- Les certificats ACME sont gérés par Traefik (si activé) — Vaultwarden ne s'en occupe pas
