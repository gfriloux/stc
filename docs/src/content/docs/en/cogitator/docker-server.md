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
virtualisation.docker.autoPrune.enable = lib.mkDefault false;  # see below
virtualisation.oci-containers.backend = "docker";
```

### Why `autoPrune` is off

`virtualisation.docker.autoPrune` can take the whole stack down at boot, so this
profile leaves it off.

Upstream, `autoPrune.persistent` defaults to `true` and `randomizedDelaySec` to
`"0"`. A timer whose weekly window was missed — an unplanned reboot, or a machine
that was off for a while — therefore fires **immediately** on the next boot, as
soon as `docker.service` is up, while the containers are still starting. At that
instant the networks this profile creates have nothing attached to them, so
`docker system prune -f` removes them as unused. Every container that references
one then fails on `network not found`, hits `StartLimitBurst`, and stays down.

Recovery is not automatic: the network units are `RemainAfterExit` oneshots with
no `ExecStop` (deliberately — see [the docker relics](/stc/en/relics/docker/)), so
nothing re-creates a network that was deleted behind their back. The same hazard
exists, more rarely, for a container that is stopped or crashlooping when the
weekly prune fires — which is why `persistent = false` alone is not enough.

Unused images grow the disk gradually and visibly; losing the network of every
container is an outage. The option stays yours to set:

```nix
# Weekly cleanup without the boot-time catch-up that creates the race.
virtualisation.docker.autoPrune = {
  enable = true;
  persistent = false;
  randomizedDelaySec = "45min";
};
```

:::caution
Even in that form, a container that is down when the prune fires can lose its
network permanently. If you enable it, make sure you know how to restart the
`docker-network-*.service` units.
:::

## Required Options

The profile enables the containers but does not supply machine-specific values.
You must set these yourself:

| Option | Why |
|--------|-----|
| `stc.relics.docker.traefik.image` | Required — STC ships no default (pin it, `# renovate`) |
| `stc.relics.docker.socketProxy.image` | Required — STC ships no default (pin it, `# renovate`) |
| `stc.relics.docker.crowdsec.image` | Required — STC ships no default (pin it, `# renovate`) |
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

  # Required: images (STC ships no defaults — pin them, renovate scans your repo)
  stc.relics.docker.traefik.image = "traefik:v3.7.6"; # renovate
  stc.relics.docker.socketProxy.image = "tecnativa/docker-socket-proxy:0.3.0"; # renovate
  stc.relics.docker.crowdsec.image = "crowdsecurity/crowdsec:v1.7.8"; # renovate

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
