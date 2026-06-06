---
title: Profil serveur Docker
description: cogitator-docker-server — pile Docker reverse proxy complète en une seule option.
---

**Module :** `stc.nixosModules.cogitator-docker-server`

Pile Docker reverse-proxy complète : Traefik + WAF CrowdSec + notifications d'échec.
Activer ceci est équivalent à activer `stc.relics.docker.traefik`, `stc.relics.docker.crowdsec`,
et `stc.relics.docker.notify` individuellement, plus la configuration du démon Docker.

Utilise les reliques individuelles directement si tu as besoin d'un contrôle plus fin —
par exemple, si tu veux Traefik sans CrowdSec, ou un provider de notification différent.

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.cogitator.docker-server.enable` | bool | `false` | Active la pile serveur Docker STC |

## Ce qu'il active

Lorsqu'il est activé, ce profil pose :

```nix
stc.relics.docker.traefik.enable = true;
stc.relics.docker.crowdsec.enable = true;
stc.relics.docker.notify.enable = true;

virtualisation.docker.enable = true;
virtualisation.docker.autoPrune.enable = true;
virtualisation.oci-containers.backend = "docker";
```

## Options requises

Le profil active les conteneurs mais ne fournit pas les valeurs spécifiques à la machine.
Tu dois les poser toi-même :

| Option | Pourquoi |
|--------|----------|
| `stc.relics.docker.traefik.acme.email` | Enregistrement Let's Encrypt |
| `stc.relics.docker.crowdsec.dataDir` | Où CrowdSec stocke ses données |
| `stc.relics.docker.notify.ntfy.topicFile` | Le topic ntfy (chemin vers le fichier de secrets) |

## Exemple d'utilisation minimal

```nix
# flake.nix
modules = [
  stc.nixosModules.cogitator-docker-server
  ./configuration.nix
];

# configuration.nix
{ config, ... }:
{
  stc.cogitator.docker-server.enable = true;

  # Requis : valeurs spécifiques à la machine
  stc.relics.docker.traefik.acme.email = "ops@example.com";
  stc.relics.docker.crowdsec.dataDir = "/srv/docker/crowdsec";
  stc.relics.docker.notify.ntfy.topicFile = config.sops.secrets."ntfy/topic".path;

  # Optionnel : ouvrir les ports pour Traefik (la relique traefik le fait aussi automatiquement)
  # stc.relics.hardening.network.allowedTCPPorts = [ 22 80 443 ];
}
```

:::note[Secrets]
`ntfy.topicFile` et `traefik.dynamicConfigFile` acceptent n'importe quel chemin de fichier.
Utilise sops-nix, agenix, ou tout autre gestionnaire de secrets — STC se fiche de
savoir comment le fichier y arrive.
:::

## Voir aussi

- [Reliques Docker](/stc/fr/relics/docker/) — Traefik, CrowdSec et notify en détail
- [Schématic : aws-ami](/stc/fr/schematics/aws-ami/) — un exemple de production complet utilisant ce profil
