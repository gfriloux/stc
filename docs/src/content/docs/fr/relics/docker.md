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
| `stc.relics.docker.traefik.enable` | bool | `false` | Active le conteneur reverse proxy Traefik |
| `stc.relics.docker.traefik.image` | string | `"traefik:v3.7.1@sha256:6b9c…"` | Image Docker, **épinglée par digest** (monte la socket brute quand le proxy est désactivé) |
| `stc.relics.docker.traefik.dataDir` | string | `"/srv/docker/traefik"` | Répertoire de base pour les logs, acme.json, conf |
| `stc.relics.docker.traefik.acme.email` | string | — | Email pour l'enregistrement ACME Let's Encrypt |
| `stc.relics.docker.traefik.enableDashboard` | bool | `false` | Active le dashboard API Traefik. Le port de l'entrypoint `traefik` (`127.0.0.1:8080`) n'est pas publié, donc l'activer seul ne l'expose pas — publie/forward le port ou ajoute une route pour y accéder. |
| `stc.relics.docker.traefik.dynamicConfigFile` | `null \| string` | `null` | Chemin vers `traefik_dynamic.yml` |

### Ce qu'elle fait

- Exécute Traefik sur les ports 80 et 443 (les deux ouverts dans le pare-feu automatiquement)
- Le port 80 HTTP redirige vers le port 443 HTTPS
- ACME/Let's Encrypt via challenge TLS, email de `acme.email`
- Dashboard désactivé par défaut ; activé, il écoute sur l'entrypoint `traefik` interne (`127.0.0.1:8080`), qui n'est **pas** publié — forward le port toi-même pour y accéder
- Logs d'accès en format JSON à `dataDir/logs/traefik.log`, rotation quotidienne (14 jours)
- Provider Docker surveillant le réseau `web` ; provider fichier lisant `traefik_dynamic.yml`
- Crée le réseau Docker `web` comme service systemd
- Quand `relics-docker-socket-proxy` est activé, Traefik parle à l'API Docker en TCP
  à travers le proxy au lieu de bind-monter le socket brut (le montage est retiré,
  un `endpoint` est ajouté au provider docker, et Traefik rejoint le réseau du proxy
  et l'attend). Sinon il bind-monte `/run/docker.sock` en lecture seule.

### Modèle pour les secrets

`dynamicConfigFile` pointe vers où ton fournisseur de secrets matérialise le fichier :

```nix
stc.relics.docker.traefik.dynamicConfigFile = config.sops.secrets."traefik/dynamic".path;
```

:::caution[Resolver ACME renommé en `letsencrypt`]
Le resolver de certificats ACME s'appelle `letsencrypt` (comme le `relics-traefik`
natif). Il s'appelait auparavant `lets-encrypt`. Dans ta config de routes dynamiques,
référence-le ainsi :

```yaml
tls:
  certResolver: letsencrypt
```

Si tu utilisais `lets-encrypt`, mets à jour ta config dynamique.
:::

---

## Docker Socket Proxy

**Module :** `stc.nixosModules.relics-docker-socket-proxy`

Exécute [`tecnativa/docker-socket-proxy`](https://github.com/Tecnativa/docker-socket-proxy),
un proxy filtrant devant le socket Docker. Le socket brut `/run/docker.sock` est
monté en lecture seule dans le conteneur du proxy **uniquement** ; les autres
conteneurs (Traefik) atteignent l'API Docker en TCP à travers le proxy sur
`tcp://docker-socket-proxy:2375`.

:::danger[Pourquoi `:ro` sur le socket ne suffit pas]
Bind-monter `/run/docker.sock` avec `:ro` ne rend **pas** l'API Docker en lecture
seule — le flag s'applique au nœud du système de fichiers, pas au protocole. Un
processus ayant accès au socket peut toujours faire des `POST` à l'API (créer un
conteneur privilégié, c.-à-d. root sur l'hôte). Le proxy est la vraie mitigation :
il désactive `POST` et ne transmet que les endpoints `GET` de la whitelist.
:::

### Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.relics.docker.socketProxy.enable` | bool | `false` | Active le proxy filtrant du socket |
| `stc.relics.docker.socketProxy.image` | string | `"tecnativa/docker-socket-proxy:0.3.0@sha256:9e4b…"` | Image Docker, **épinglée par digest** (ce conteneur détient la socket Docker) |
| `stc.relics.docker.socketProxy.network` | string | `"socket-proxy"` | Réseau Docker partagé avec les clients (ex. Traefik) |
| `stc.relics.docker.socketProxy.permissions` | attrs de bool | `{ CONTAINERS = true; NETWORKS = true; EVENTS = true; PING = true; VERSION = true; }` | Sections de l'API Docker exposées. `POST` est toujours forcé à off. |

### Ce qu'elle fait

- Exécute le conteneur proxy avec le socket brut monté en lecture seule
- N'expose que les sections `GET` de la whitelist (les défauts couvrent le provider docker de Traefik)
- Force `POST = "0"` quelles que soient les `permissions`
- Crée le réseau Docker `network` comme service systemd, ordonné avant le proxy

### Utilisation

Active-le aux côtés de Traefik et le câblage est automatique :

```nix
stc.relics.docker = {
  traefik.enable = true;
  socketProxy.enable = true;   # Traefik utilise désormais le proxy, plus de socket brut
};
```

Le profil [`cogitator-docker-server`](/stc/fr/cogitator/docker-server/) l'active par défaut.

---

## CrowdSec

**Module :** `stc.nixosModules.relics-docker-crowdsec`

Exécute CrowdSec comme couche IDS/IPS comportementale (basée sur les logs, ce
n'est pas un WAF : STC ne configure pas le composant AppSec). Lit les logs d'accès
Traefik pour détecter
et bloquer le trafic malveillant. Quand Traefik et CrowdSec sont tous les deux activés,
le plugin bouncer CrowdSec est automatiquement câblé dans la config statique Traefik,
et le service systemd `traefik` reçoit `After = crowdsec.service` (ordonnancement) et
`Wants = crowdsec.service` (dépendance souple — un CrowdSec en panne n'entraîne jamais
la chute du reverse proxy).

CrowdSec rejoint le réseau Docker `web`. Quand Traefik est activé, c'est lui qui
possède ce réseau ; quand CrowdSec tourne sans Traefik, il le crée lui-même.

### Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.relics.docker.crowdsec.enable` | bool | `false` | Active le conteneur IDS/IPS CrowdSec |
| `stc.relics.docker.crowdsec.image` | string | `"crowdsecurity/crowdsec:v1.7.8@sha256:2f52…"` | Image Docker, **épinglée par digest** |
| `stc.relics.docker.crowdsec.dataDir` | string | — | Répertoire de base pour les données et la config CrowdSec |
| `stc.relics.docker.crowdsec.envFile` | `null \| string` | `null` | Chemin vers le fichier d'environnement avec les secrets |

### Modèle pour les secrets

```nix
stc.relics.docker.crowdsec.envFile = config.sops.secrets."crowdsec/env".path;
```

### Intégration CrowdSec-Traefik

Quand `stc.relics.docker.crowdsec.enable = true` et `stc.relics.docker.traefik.enable = true` :

1. Le plugin bouncer CrowdSec (`maxlerebourg/crowdsec-bouncer-traefik-plugin v1.5.1`)
   est automatiquement ajouté à la config statique Traefik sous `experimental.plugins`
2. Traefik est ordonné après CrowdSec, mais seulement via `Wants` (souple) — voir ci-dessus
3. CrowdSec monte le répertoire de logs Traefik en lecture seule pour parser les logs d'accès

Aucun câblage manuel requis.

---

## Docker Notify

**Module :** `stc.nixosModules.relics-docker-notify`

Exécute une commande de notification fournie par le consommateur quand un
conteneur surveillé échoue, et redémarre automatiquement les conteneurs malsains.

La relique est **agnostique au transport** : STC possède le câblage réutilisable
(health-watch, `OnFailure`, politique de redémarrage, label opt-in) mais pas le
transport de notification. Tu fournis `notifyCommand` ; elle reçoit tout par
l'environnement et lit ses propres secrets, exactement comme le modèle de secrets
`*File`.

Les conteneurs optent en posant le label `stc.docker/health-watch = "true"`. La relique
parcourt `virtualisation.oci-containers.containers` pour ce label et câble
automatiquement la surveillance.

### Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.relics.docker.notify.enable` | bool | `false` | Active les notifications d'échec et le redémarrage des conteneurs malsains |
| `stc.relics.docker.notify.hostname` | string | `config.networking.hostName` | Valeur exposée à `notifyCommand` via `STC_NOTIFY_HOSTNAME` |
| `stc.relics.docker.notify.watchLabel` | string | `"stc.docker/health-watch"` | Label marquant les conteneurs pour la surveillance |
| `stc.relics.docker.notify.notifyCommand` | lines | `""` | Commande shell exécutée à l'échec. Requise quand la relique est activée. |

### La commande de notification

`notifyCommand` s'exécute quand un service surveillé échoue. Elle reçoit le
contexte par l'environnement (pas d'arguments positionnels) :

| Variable | Signification |
|----------|---------------|
| `STC_NOTIFY_SERVICE` | Le service systemd passé en état failed |
| `STC_NOTIFY_HOSTNAME` | La valeur de l'option `hostname` |

STC est agnostique au backend — ntfy, un webhook, un e-mail, n'importe quoi. La
commande lit tout secret nécessaire depuis son propre fichier. ntfy n'est qu'un
exemple :

```nix
stc.relics.docker.notify = {
  enable = true;
  notifyCommand = ''
    ${pkgs.curl}/bin/curl -s \
      -H "Title: [$STC_NOTIFY_HOSTNAME] $STC_NOTIFY_SERVICE failed" \
      -d "$STC_NOTIFY_SERVICE entered failed state" \
      "https://ntfy.sh/$(cat ${config.sops.secrets."ntfy/topic".path})"
  '';
};
```

:::caution[ntfy.sh public dans l'exemple]
Le snippet ci-dessus poste vers le service public `https://ntfy.sh` : les
notifications d'échec (hostname et noms de services en échec) quittent ton réseau
vers un tiers, et le topic est l'unique secret — quiconque le devine peut lire tes
alertes. Pour tout ce qui est sensible, auto-héberge ntfy et/ou utilise un topic
long et aléatoire.
:::

### Fonctionnement de la surveillance de santé

Pour chaque conteneur avec le label de surveillance :
- Un timer systemd se déclenche toutes les 30 secondes (démarrant 4 minutes après le boot)
- Il vérifie `docker inspect` pour le statut de santé `unhealthy`
- Si malsain, le conteneur est tué (Docker le redémarre selon sa politique de redémarrage)
- En cas d'échec du service, `stc-notify-failure@<service>.service` exécute `notifyCommand`

:::caution[Un conteneur durablement malsain finit arrêté]
L'unité surveillée utilise `Restart=on-failure` avec `StartLimitBurst=3` /
`StartLimitIntervalSec=300s`. Un conteneur qui reste `unhealthy` est tué toutes
les 30s ; trois kills en ~90s atteignent la limite et systemd cesse de le
redémarrer — il reste alors **arrêté**. C'est délibéré (mieux qu'un crash-loop),
mais le seul signal est l'alerte `notifyCommand`. Un service durablement cassé, y
compris l'IDS/IPS CrowdSec, peut finir définitivement arrêté sans autre alerte —
assure-toi que quelqu'un reçoit réellement ces alertes.
:::

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
{ config, pkgs, ... }:
{
  stc.relics.docker = {
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
      notifyCommand = ''
        ${pkgs.curl}/bin/curl -s \
          -d "$STC_NOTIFY_SERVICE failed on $STC_NOTIFY_HOSTNAME" \
          "https://ntfy.sh/$(cat ${config.sops.secrets."ntfy/topic".path})"
      '';
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
