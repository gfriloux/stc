---
title: Docker Server Profile
description: cogitator-docker-server — full Docker reverse proxy stack in one option.
---

**Module:** `stc.nixosModules.cogitator-docker-server`

Full Docker reverse-proxy stack: Traefik + CrowdSec WAF + failure notifications.
Enabling this is equivalent to enabling `stc.docker.traefik`, `stc.docker.crowdsec`,
and `stc.docker.notify` individually, plus configuring the Docker daemon.

Use the individual relics directly if you need finer control — for example, if you
want Traefik without CrowdSec, or a different notify provider.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.cogitator.docker-server.enable` | bool | `false` | Enable the STC Docker server stack |

## What It Enables

When enabled, this profile sets:

```nix
stc.docker.traefik.enable = true;
stc.docker.crowdsec.enable = true;
stc.docker.notify.enable = true;

virtualisation.docker.enable = true;
virtualisation.docker.autoPrune.enable = true;
virtualisation.oci-containers.backend = "docker";
```

## Required Options

The profile enables the containers but does not supply machine-specific values.
You must set these yourself:

| Option | Why |
|--------|-----|
| `stc.docker.traefik.acme.email` | Let's Encrypt registration |
| `stc.docker.crowdsec.dataDir` | Where CrowdSec stores its data |
| `stc.docker.notify.ntfy.topicFile` | The ntfy topic (secrets file path) |

## Minimal Usage Example

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

  # Required: machine-specific values
  stc.docker.traefik.acme.email = "ops@example.com";
  stc.docker.crowdsec.dataDir = "/srv/docker/crowdsec";
  stc.docker.notify.ntfy.topicFile = config.sops.secrets."ntfy/topic".path;

  # Optional: open ports for Traefik (traefik relic also does this automatically)
  # stc.hardening.network.allowedTCPPorts = [ 22 80 443 ];
}
```

:::note[Secrets]
`ntfy.topicFile` and `traefik.dynamicConfigFile` accept any file path.
Use sops-nix, agenix, or any other secrets manager — STC does not care how the
file gets there.
:::

## See Also

- [Docker relics](/en/relics/docker/) — Traefik, CrowdSec, and notify in detail
- [Schematic: aws-ami](/en/schematics/aws-ami/) — a complete production example using this profile
