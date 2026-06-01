---
title: Reliques Docker
description: Traefik, CrowdSec et notifications d'échec de conteneurs — la pile Docker reverse proxy STC.
---

Trois reliques Docker forment une pile reverse proxy complète. Chacune peut être
utilisée indépendamment, mais elles sont conçues pour fonctionner ensemble.

## Traefik

**Module :** `stc.nixosModules.relics-docker-traefik`

Exécute Traefik v3 dans un conteneur Docker comme reverse proxy. Génère la
configuration statique à partir des options Nix. La configuration dynamique
(routes, middlewares, certificats) est fournie à l'exécution via un fichier séparé.

### Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.docker.traefik.enable` | bool | `false` | Active le conteneur reverse proxy Traefik |
| `stc.docker.traefik.image` | string | `"traefik:v3.7.1"` | Image Docker |
| `stc.docker.traefik.dataDir` | string | `"/srv/docker/traefik"` | Répertoire de base pour les logs, acme.json, conf |
| `stc.docker.traefik.acme.email` | string | — | Email pour l'enregistrement ACME Let's Encrypt |
| `stc.docker.traefik.enableDashboard` | bool | `true` | Active le dashboard API Traefik sur `127.0.0.1:8080`. Désactiver pour réduire la surface d'attaque en production. |
| `stc.docker.traefik.dynamicConfigFile` | `null \| string` | `null` | Chemin vers `traefik_dynamic.yml` |

### Ce qu'elle fait

- Exécute Traefik sur les ports 80 et 443 (les deux ouverts dans le pare-feu automatiquement)
- Le port 80 HTTP redirige vers le port 443 HTTPS
- ACME/Let's Encrypt via challenge TLS, email de `acme.email`
- Dashboard sur `127.0.0.1:8080` (localhost uniquement)
- Logs d'accès en format JSON à `dataDir/logs/traefik.log`, rotation quotidienne (14 jours)
- Provider Docker surveillant le réseau `web` ; provider fichier lisant `traefik_dynamic.yml`
- Crée le réseau Docker `web` comme service systemd

### Modèle pour les secrets

`dynamicConfigFile` pointe vers où ton fournisseur de secrets matérialise le fichier :

```nix
stc.docker.traefik.dynamicConfigFile = config.sops.secrets."traefik/dynamic".path;
```

---

## CrowdSec

**Module :** `stc.nixosModules.relics-docker-crowdsec`

Exécute CrowdSec comme couche WAF/IDS. Lit les logs d'accès Traefik pour détecter
et bloquer le trafic malveillant. Quand Traefik et CrowdSec sont tous les deux activés,
le plugin bouncer CrowdSec est automatiquement câblé dans la config statique Traefik,
et le service systemd `traefik` reçoit `After = crowdsec.service` / `Requires = crowdsec.service`.

### Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.docker.crowdsec.enable` | bool | `false` | Active le conteneur WAF CrowdSec |
| `stc.docker.crowdsec.image` | string | `"crowdsecurity/crowdsec:v1.7.8"` | Image Docker |
| `stc.docker.crowdsec.dataDir` | string | — | Répertoire de base pour les données et la config CrowdSec |
| `stc.docker.crowdsec.envFile` | `null \| string` | `null` | Chemin vers le fichier d'environnement avec les secrets |

### Modèle pour les secrets

```nix
stc.docker.crowdsec.envFile = config.sops.secrets."crowdsec/env".path;
```

### Intégration CrowdSec-Traefik

Quand `stc.docker.crowdsec.enable = true` et `stc.docker.traefik.enable = true` :

1. Le plugin bouncer CrowdSec (`maxlerebourg/crowdsec-bouncer-traefik-plugin v1.5.1`)
   est automatiquement ajouté à la config statique Traefik sous `experimental.plugins`
2. Traefik attend que CrowdSec soit sain avant de démarrer
3. CrowdSec monte le répertoire de logs Traefik en lecture seule pour parser les logs d'accès

Aucun câblage manuel requis.

---

## Docker Notify

**Module :** `stc.nixosModules.relics-docker-notify`

Envoie des notifications push ntfy quand un conteneur surveillé échoue, et
redémarre automatiquement les conteneurs malsains.

Les conteneurs optent en posant le label `stc.docker/health-watch = "true"`. La relique
parcourt `virtualisation.oci-containers.containers` pour ce label et câble
automatiquement la surveillance.

### Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.docker.notify.enable` | bool | `false` | Active les notifications d'échec via ntfy |
| `stc.docker.notify.hostname` | string | `config.networking.hostName` | Hostname dans les titres de notification |
| `stc.docker.notify.watchLabel` | string | `"stc.docker/health-watch"` | Label marquant les conteneurs pour la surveillance |
| `stc.docker.notify.ntfy.baseUrl` | string | `"https://ntfy.sh"` | URL de base du serveur ntfy |
| `stc.docker.notify.ntfy.topicFile` | string | — | Chemin vers le fichier contenant le nom du topic ntfy |

### Modèle pour les secrets

```nix
stc.docker.notify.ntfy.topicFile = config.sops.secrets."ntfy/topic".path;
```

### Fonctionnement de la surveillance de santé

Pour chaque conteneur avec le label de surveillance :
- Un timer systemd se déclenche toutes les 30 secondes (démarrant 4 minutes après le boot)
- Il vérifie `docker inspect` pour le statut de santé `unhealthy`
- Si malsain, le conteneur est tué (Docker le redémarre selon sa politique de redémarrage)
- En cas d'échec du service, `stc-notify-failure@<service>.service` envoie une notification ntfy

### Opt-in basé sur les labels

Pose le label sur tout conteneur que tu veux surveiller :

```nix
virtualisation.oci-containers.containers.myapp = {
  image = "myapp:latest";
  labels = {
    "stc.docker/health-watch" = "true";
  };
  extraOptions = stc.lib.docker.mkHealthCheck {
    cmd = "curl -sf http://localhost:8080/health";
  };
};
```

---

## Exemple de pile complète

```nix
# flake.nix
modules = [
  stc.nixosModules.relics-docker-traefik
  stc.nixosModules.relics-docker-crowdsec
  stc.nixosModules.relics-docker-notify
  ./configuration.nix
];

# configuration.nix
{ config, ... }:
{
  stc.docker = {
    traefik = {
      enable = true;
      acme.email = "ops@example.com";
      dynamicConfigFile = config.sops.secrets."traefik/dynamic".path;
    };

    crowdsec = {
      enable = true;
      dataDir = "/srv/docker/crowdsec";
      envFile = config.sops.secrets."crowdsec/env".path;
    };

    notify = {
      enable = true;
      ntfy.topicFile = config.sops.secrets."ntfy/topic".path;
    };
  };

  virtualisation = {
    docker = {
      enable = true;
      autoPrune.enable = true;
    };
    oci-containers.backend = "docker";
  };
}
```

:::tip[cogitator-docker-server]
Le profil [`cogitator-docker-server`](/stc/fr/cogitator/docker-server/) active les
trois reliques et configure Docker en une seule option. Utilise-le quand les
valeurs par défaut te conviennent.
:::

---

## stc.lib.docker

Deux helpers sont disponibles pour les consommateurs qui écrivent leurs propres conteneurs :

### `stc.lib.docker.mkHealthCheck`

Construit les flags `--health-*` pour `extraOptions` :

```nix
extraOptions = stc.lib.docker.mkHealthCheck {
  cmd = "curl -sf http://localhost:8080/health";
  interval = "30s";    # défaut
  timeout = "10s";     # défaut
  startPeriod = "30s"; # défaut
  retries = 3;         # défaut
};
```

### `stc.lib.docker.mkNetwork`

Crée un réseau Docker idempotent comme service systemd :

```nix
systemd.services."docker-network-mynet" =
  stc.lib.docker.mkNetwork pkgs "mynet";
```
