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
| `stc.relics.docker.traefik.enable` | bool | `false` | Enable Traefik reverse proxy container |
| `stc.relics.docker.traefik.image` | string | `"traefik:v3.7.1@sha256:6b9c…"` | Docker image, **pinned by digest** (mounts the raw socket when the proxy is off) |
| `stc.relics.docker.traefik.dataDir` | string | `"/srv/docker/traefik"` | Base directory for logs, acme.json, conf |
| `stc.relics.docker.traefik.acme.email` | string | — | Email for Let's Encrypt ACME registration |
| `stc.relics.docker.traefik.enableDashboard` | bool | `false` | Enable the Traefik API dashboard. The `traefik` entrypoint port (`127.0.0.1:8080`) is not published, so this alone does not expose it — publish/forward the port or add a route to reach it. |
| `stc.relics.docker.traefik.dynamicConfigFile` | `null \| string` | `null` | Path to `traefik_dynamic.yml` |

### What It Does

- Runs Traefik on ports 80 and 443 (both opened in the firewall automatically)
- HTTP on port 80 redirects to HTTPS on port 443
- ACME/Let's Encrypt via TLS challenge, email from `acme.email`
- Dashboard off by default; when enabled it binds the in-container `traefik` entrypoint (`127.0.0.1:8080`), which is **not** published — forward the port yourself to reach it
- Access logs in JSON format at `dataDir/logs/traefik.log`, rotated daily (14 days)
- Docker provider watching the `web` network; file provider reading `traefik_dynamic.yml`
- Creates the `web` Docker network as a systemd service
- When `relics-docker-socket-proxy` is enabled, Traefik talks to the Docker API
  over TCP through the proxy instead of bind-mounting the raw socket (the mount is
  dropped, an `endpoint` is added to the docker provider, and Traefik joins the
  proxy network and waits for it). Otherwise it bind-mounts `/run/docker.sock` read-only.

### Secrets Pattern

`dynamicConfigFile` points to wherever your secrets provider materialises the file:

```nix
stc.relics.docker.traefik.dynamicConfigFile = config.sops.secrets."traefik/dynamic".path;
```

:::caution[ACME resolver renamed to `letsencrypt`]
The ACME cert resolver is named `letsencrypt` (matching the native `relics-traefik`).
It was previously `lets-encrypt`. In your dynamic route config, reference it as:

```yaml
tls:
  certResolver: letsencrypt
```

If you were using `lets-encrypt`, update your dynamic config.
:::

---

## Docker Socket Proxy

**Module:** `stc.nixosModules.relics-docker-socket-proxy`

Runs [`tecnativa/docker-socket-proxy`](https://github.com/Tecnativa/docker-socket-proxy),
a filtering proxy in front of the Docker socket. The raw `/run/docker.sock` is
mounted read-only into the proxy container **only**; other containers (Traefik)
reach the Docker API over TCP through the proxy at `tcp://docker-socket-proxy:2375`.

:::danger[Why `:ro` on the socket is not enough]
Bind-mounting `/run/docker.sock` with `:ro` does **not** make the Docker API
read-only — the flag applies to the filesystem node, not the protocol. A process
with access to the socket can still `POST` to the API (create a privileged
container, i.e. root on the host). The proxy is the real mitigation: it disables
`POST` and forwards only the whitelisted `GET` endpoints.
:::

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.docker.socketProxy.enable` | bool | `false` | Enable the filtering socket proxy |
| `stc.relics.docker.socketProxy.image` | string | `"tecnativa/docker-socket-proxy:0.3.0@sha256:9e4b…"` | Docker image, **pinned by digest** (this container holds the Docker socket) |
| `stc.relics.docker.socketProxy.network` | string | `"socket-proxy"` | Docker network shared with clients (e.g. Traefik) |
| `stc.relics.docker.socketProxy.permissions` | attrs of bool | `{ CONTAINERS = true; NETWORKS = true; EVENTS = true; PING = true; VERSION = true; }` | Docker API sections to expose. `POST` is always forced off. |

### What It Does

- Runs the proxy container with the raw socket mounted read-only
- Exposes only the whitelisted `GET` sections (defaults cover the Traefik docker provider)
- Forces `POST = "0"` regardless of `permissions`
- Creates the `network` Docker network as a systemd service, ordered before the proxy

### Usage

Enable it alongside Traefik and the wiring is automatic:

```nix
stc.relics.docker = {
  traefik.enable = true;
  socketProxy.enable = true;   # Traefik now uses the proxy, no raw socket
};
```

The [`cogitator-docker-server`](/stc/en/cogitator/docker-server/) profile enables
this by default.

---

## CrowdSec

**Module:** `stc.nixosModules.relics-docker-crowdsec`

Runs CrowdSec as a behavioral IDS/IPS layer (log-based, not a WAF: STC does not
configure the AppSec component). Reads Traefik access logs to detect and block
malicious traffic. When both Traefik and CrowdSec are enabled, the CrowdSec bouncer
plugin is automatically wired into the Traefik static config, and the `traefik`
systemd service gets `After = crowdsec.service` (ordering) and `Wants = crowdsec.service`
(a soft dependency — a failing CrowdSec never drags the reverse proxy down with it).

CrowdSec joins the `web` Docker network. When Traefik is enabled it owns that
network; when CrowdSec runs without Traefik, it creates the network itself.

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.docker.crowdsec.enable` | bool | `false` | Enable CrowdSec IDS/IPS container |
| `stc.relics.docker.crowdsec.image` | string | `"crowdsecurity/crowdsec:v1.7.8@sha256:2f52…"` | Docker image, **pinned by digest** |
| `stc.relics.docker.crowdsec.dataDir` | string | — | Base directory for CrowdSec data and config |
| `stc.relics.docker.crowdsec.envFile` | `null \| string` | `null` | Path to environment file with secrets |

### Secrets Pattern

```nix
stc.relics.docker.crowdsec.envFile = config.sops.secrets."crowdsec/env".path;
```

### CrowdSec-Traefik Integration

When `stc.relics.docker.crowdsec.enable = true` and `stc.relics.docker.traefik.enable = true`:

1. The CrowdSec bouncer plugin (`maxlerebourg/crowdsec-bouncer-traefik-plugin v1.5.1`)
   is automatically added to Traefik's static config under `experimental.plugins`
2. Traefik is ordered after CrowdSec, but only via `Wants` (soft) — see above
3. CrowdSec mounts the Traefik log directory read-only to parse access logs

No manual wiring required.

---

## Docker Notify

**Module:** `stc.nixosModules.relics-docker-notify`

Runs a consumer-supplied notification command when a watched Docker container
fails, and automatically restarts unhealthy containers.

The relic is **transport-agnostic**: STC owns the reusable wiring (health-watch,
`OnFailure`, restart policy, opt-in label) but not the notification transport.
You provide `notifyCommand`; it receives everything through the environment and
reads its own secrets, exactly like the `*File` secrets pattern.

Containers opt in by setting the label `stc.docker/health-watch = "true"`. The relic
scans `virtualisation.oci-containers.containers` for this label and wires up the
monitoring automatically.

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.docker.notify.enable` | bool | `false` | Enable failure notifications and unhealthy-container restarts |
| `stc.relics.docker.notify.hostname` | string | `config.networking.hostName` | Value exposed to `notifyCommand` as `STC_NOTIFY_HOSTNAME` |
| `stc.relics.docker.notify.watchLabel` | string | `"stc.docker/health-watch"` | Label marking containers for health monitoring |
| `stc.relics.docker.notify.notifyCommand` | lines | `""` | Shell command run on failure. Required when enabled. |

### The notification command

`notifyCommand` runs when a watched service fails. It receives the context
through the environment (no positional arguments):

| Variable | Meaning |
|----------|---------|
| `STC_NOTIFY_SERVICE` | The systemd service that entered the failed state |
| `STC_NOTIFY_HOSTNAME` | The `hostname` option value |

STC is agnostic to the backend — ntfy, a webhook, e-mail, anything. Read any
secret the command needs from its own file. ntfy is just one example:

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

:::caution[Public ntfy.sh in the example]
The snippet above posts to the public `https://ntfy.sh`: failure notifications
(hostname and failed service names) leave your network to a third party, and the
topic is the only secret — anyone who guesses it can read your alerts. For
anything sensitive, self-host ntfy and/or use a long random topic.
:::

### How Health Watching Works

For each container with the watch label:
- A systemd timer fires every 30 seconds (starting 4 minutes after boot)
- It checks `docker inspect` for `unhealthy` health status
- If unhealthy, the container is killed (Docker restarts it per its restart policy)
- On service failure, `stc-notify-failure@<service>.service` runs `notifyCommand`

:::caution[A persistently-unhealthy container ends up stopped]
The watched unit uses `Restart=on-failure` with `StartLimitBurst=3` /
`StartLimitIntervalSec=300s`. A container that stays `unhealthy` is killed every
30s; three kills inside ~90s trip the limit and systemd stops restarting it — it
then stays **down**. This is deliberate (better than crash-looping), but the
only signal is the `notifyCommand` alert. A persistently-broken service,
including the CrowdSec IDS/IPS, can end up permanently stopped with nothing else
flagging it — make sure someone actually receives those alerts.
:::

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
The [`cogitator-docker-server`](/stc/en/cogitator/docker-server/) profile enables all
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
