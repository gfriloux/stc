---
title: Docker Server Profile
description: cogitator-docker-server — full Docker reverse proxy stack in one option.
---

**Module:** `stc.nixosModules.cogitator-docker-server`

Full Docker reverse-proxy stack: Traefik + a filtering socket-proxy + CrowdSec IDS/IPS,
with optional failure notifications. Enabling this is equivalent to enabling
`stc.relics.docker.traefik`, `stc.relics.docker.socketProxy`, and
`stc.relics.docker.crowdsec` individually, plus configuring the Docker daemon.

Use the individual relics directly if you need finer control — for example, if you
want Traefik without CrowdSec, or a different notify provider.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.cogitator.docker-server.enable` | bool | `false` | Enable the STC Docker server stack |
| `stc.cogitator.docker-server.notify.enable` | bool | `false` | Enable failure notifications for the stack (requires `notifyCommand`) |

## What It Enables

When enabled, this profile sets:

```nix
stc.relics.docker.traefik.enable = true;
stc.relics.docker.socketProxy.enable = true;  # Traefik uses the proxy, not the raw socket
stc.relics.docker.crowdsec.enable = true;
stc.relics.docker.notify.enable = cfg.notify.enable;  # off unless you opt in

virtualisation.docker.enable = true;
virtualisation.docker.autoPrune.enable = true;
virtualisation.oci-containers.backend = "docker";
```

## Required Options

The profile enables the containers but does not supply machine-specific values.
You must set these yourself:

| Option | Why |
|--------|-----|
| `stc.relics.docker.traefik.acme.email` | Let's Encrypt registration |
| `stc.relics.docker.crowdsec.dataDir` | Where CrowdSec stores its data |
| `stc.relics.docker.notify.notifyCommand` | Only when `notify.enable = true` — the alert transport |

## Minimal Usage Example

```nix
# flake.nix
modules = [
  stc.nixosModules.cogitator-docker-server
  ./configuration.nix
];

# configuration.nix
{ config, pkgs, ... }:
{
  stc.cogitator.docker-server.enable = true;

  # Required: machine-specific values
  stc.relics.docker.traefik.acme.email = "ops@example.com";
  stc.relics.docker.crowdsec.dataDir = "/srv/docker/crowdsec";

  # Optional: failure notifications (off by default). When enabled, supply the
  # transport — it receives STC_NOTIFY_SERVICE / STC_NOTIFY_HOSTNAME.
  # stc.cogitator.docker-server.notify.enable = true;
  # stc.relics.docker.notify.notifyCommand = ''
  #   ${pkgs.curl}/bin/curl -s \
  #     -d "$STC_NOTIFY_SERVICE failed on $STC_NOTIFY_HOSTNAME" \
  #     "https://ntfy.sh/$(cat ${config.sops.secrets."ntfy/topic".path})"
  # '';

  # Optional: open ports for Traefik (traefik relic also does this automatically)
  # stc.relics.hardening.network.allowedTCPPorts = [ 22 80 443 ];
}
```

:::note[Secrets]
`notifyCommand` and `traefik.dynamicConfigFile` accept any file path.
Use sops-nix, agenix, or any other secrets manager — STC does not care how the
file gets there.
:::

## See Also

- [Docker relics](/stc/en/relics/docker/) — Traefik, socket-proxy, CrowdSec, and notify in detail
- [Schematic: aws-ami](/stc/en/schematics/aws-ami/) — a complete production example using this profile
