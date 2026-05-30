---
title: Docker Relics
description: Traefik, CrowdSec, and container failure notifications — the STC Docker reverse proxy stack.
---

Three Docker relics form a complete reverse proxy stack. Each can be used
independently, but they are designed to work together.

## Traefik

**Module:** `stc.nixosModules.relics-docker-traefik`

Runs Traefik v3 in a Docker container as a reverse proxy. Generates the static
config from Nix options. Dynamic config (routes, middlewares, certificates) is
supplied at runtime via a separate file.

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.docker.traefik.enable` | bool | `false` | Enable Traefik reverse proxy container |
| `stc.docker.traefik.image` | string | `"traefik:v3.7.1"` | Docker image |
| `stc.docker.traefik.dataDir` | string | `"/srv/docker/traefik"` | Base directory for logs, acme.json, conf |
| `stc.docker.traefik.acme.email` | string | — | Email for Let's Encrypt ACME registration |
| `stc.docker.traefik.dynamicConfigFile` | `null \| string` | `null` | Path to `traefik_dynamic.yml` |

### What It Does

- Runs Traefik on ports 80 and 443 (both opened in the firewall automatically)
- HTTP on port 80 redirects to HTTPS on port 443
- ACME/Let's Encrypt via TLS challenge, email from `acme.email`
- Dashboard on `127.0.0.1:8080` (localhost only)
- Access logs in JSON format at `dataDir/logs/traefik.log`, rotated daily (14 days)
- Docker provider watching the `web` network; file provider reading `traefik_dynamic.yml`
- Creates the `web` Docker network as a systemd service

### Secrets Pattern

`dynamicConfigFile` points to wherever your secrets provider materialises the file:

```nix
stc.docker.traefik.dynamicConfigFile = config.sops.secrets."traefik/dynamic".path;
```

---

## CrowdSec

**Module:** `stc.nixosModules.relics-docker-crowdsec`

Runs CrowdSec as a WAF/IDS layer. Reads Traefik access logs to detect and block
malicious traffic. When both Traefik and CrowdSec are enabled, the CrowdSec bouncer
plugin is automatically wired into the Traefik static config, and the `traefik`
systemd service gets `After = crowdsec.service` / `Requires = crowdsec.service`.

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.docker.crowdsec.enable` | bool | `false` | Enable CrowdSec WAF container |
| `stc.docker.crowdsec.image` | string | `"crowdsecurity/crowdsec:v1.7.8"` | Docker image |
| `stc.docker.crowdsec.dataDir` | string | — | Base directory for CrowdSec data and config |
| `stc.docker.crowdsec.envFile` | `null \| string` | `null` | Path to environment file with secrets |

### Secrets Pattern

```nix
stc.docker.crowdsec.envFile = config.sops.secrets."crowdsec/env".path;
```

### CrowdSec-Traefik Integration

When `stc.docker.crowdsec.enable = true` and `stc.docker.traefik.enable = true`:

1. The CrowdSec bouncer plugin (`maxlerebourg/crowdsec-bouncer-traefik-plugin v1.5.1`)
   is automatically added to Traefik's static config under `experimental.plugins`
2. Traefik waits for CrowdSec to be healthy before starting
3. CrowdSec mounts the Traefik log directory read-only to parse access logs

No manual wiring required.

---

## Docker Notify

**Module:** `stc.nixosModules.relics-docker-notify`

Sends ntfy push notifications when a watched Docker container fails, and
automatically restarts unhealthy containers.

Containers opt in by setting the label `stc.docker/health-watch = "true"`. The relic
scans `virtualisation.oci-containers.containers` for this label and wires up the
monitoring automatically.

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.docker.notify.enable` | bool | `false` | Enable failure notifications via ntfy |
| `stc.docker.notify.hostname` | string | `config.networking.hostName` | Hostname shown in notification titles |
| `stc.docker.notify.watchLabel` | string | `"stc.docker/health-watch"` | Label marking containers for health monitoring |
| `stc.docker.notify.ntfy.baseUrl` | string | `"https://ntfy.sh"` | ntfy server base URL |
| `stc.docker.notify.ntfy.topicFile` | string | — | Path to file containing the ntfy topic name |

### Secrets Pattern

```nix
stc.docker.notify.ntfy.topicFile = config.sops.secrets."ntfy/topic".path;
```

### How Health Watching Works

For each container with the watch label:
- A systemd timer fires every 30 seconds (starting 4 minutes after boot)
- It checks `docker inspect` for `unhealthy` health status
- If unhealthy, the container is killed (Docker restarts it per its restart policy)
- On service failure, `stc-notify-failure@<service>.service` sends an ntfy notification

### Label-Based Opt-In

Set the label on any container you want monitored:

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

## Full Stack Example

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
The [`cogitator-docker-server`](/en/cogitator/docker-server/) profile enables all
three relics and sets up Docker in one option. Use it when the defaults suit you.
:::

---

## stc.lib.docker

Two helpers are available for consumers writing their own containers:

### `stc.lib.docker.mkHealthCheck`

Builds the `--health-*` flags for `extraOptions`:

```nix
extraOptions = stc.lib.docker.mkHealthCheck {
  cmd = "curl -sf http://localhost:8080/health";
  interval = "30s";    # default
  timeout = "10s";     # default
  startPeriod = "30s"; # default
  retries = 3;         # default
};
```

### `stc.lib.docker.mkNetwork`

Creates an idempotent Docker network as a systemd service:

```nix
systemd.services."docker-network-mynet" =
  stc.lib.docker.mkNetwork pkgs "mynet";
```
