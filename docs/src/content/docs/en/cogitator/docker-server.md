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
stc.relics.docker.guards.enable = lib.mkDefault true; # warn on containers that bypass Traefik or the proxy
stc.relics.preSwitchChecks.enable = true;             # see below
stc.relics.serverSurvivability.enable = lib.mkDefault true;  # reboot rather than wait for a console
stc.relics.nixHousekeeping.enable = lib.mkDefault true;      # bounded store and journal

virtualisation.docker.enable = true;
virtualisation.docker.autoPrune.enable = lib.mkDefault false;  # see below
virtualisation.oci-containers.backend = "docker";
```

### Why the pre-switch checks are part of the profile

A Docker server is the shape those checks guard: a remote host, deployed with a
command that differs from its neighbour's by one flake attribute. Activate the
wrong closure here and you get wrong containers, wrong Traefik routers, wrong
users, wrong secrets — and `nixos-rebuild --target-host` prints no diff to warn
you.

So this profile turns on
[`stc.relics.preSwitchChecks`](/stc/en/relics/pre-switch-checks/): the switch
aborts, with the old system still running, unless the incoming closure belongs to
the machine activating it.

:::caution[It can abort a deploy that used to work]
If the hostname your machine actually runs differs from its
`networking.hostName` — overwritten by DHCP or `cloud-init`, or simply never
corrected — the next `nixos-rebuild` on that host aborts. The build still
succeeds; only activation stops. Fix the mismatch, set
`stc.relics.preSwitchChecks.hostnameGuard = false;`, or pass `NIXOS_NO_CHECK=1`
for one deploy. The relic page covers all three.
:::

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

  # Other ports: Traefik's 80 and 443 are opened by the traefik relic, SSH by
  # services.openssh.
  # networking.firewall.allowedTCPPorts = [ 8443 ];
}
```

:::note[Secrets]
`notifyCommand` and `traefik.dynamicConfigFile` accept any file path.
Use sops-nix, agenix, or any other secrets manager — STC does not care how the
file gets there.
:::

## Running the stack without CrowdSec or the socket proxy

Since `v0.18.0`, `socketProxy`, `crowdsec` and `preSwitchChecks` are enabled with
`lib.mkDefault`:

```nix
stc.cogitator.docker-server.enable = true;

# No CrowdSec on this host — and no CrowdSec image needed either.
stc.relics.docker.crowdsec.enable = false;
```

That second line is the part worth knowing. The Docker relics **assert** on a
missing image, so before `v0.18.0` declining CrowdSec was not just a matter of
priority: you had to hand CrowdSec an image you never intended to run, or write
`lib.mkForce`. `traefik` stays pinned on purpose — a reverse-proxied container
host is what this profile *is*. See
[Overridable defaults](/stc/en/reference/overridable-defaults/).

:::danger[Declining the socket proxy is not free]
The socket proxy exists so Traefik never touches the raw Docker API. With
`socketProxy.enable = false`, the Traefik relic falls back to bind-mounting
`/run/docker.sock` into the container read-only — so Traefik gets direct access
to the Docker API, and a compromise of that container is a path to host root.

That trade is yours to make (a single-tenant host where you accept it), but make
it knowingly. Until `v0.18.0` the priority conflict forced the question; now
only this paragraph does.
:::

## See Also

- [Docker relics](/stc/en/relics/docker/) — Traefik, socket-proxy, CrowdSec, and notify in detail
- [Overridable defaults](/stc/en/reference/overridable-defaults/) — which of this profile's relics you can decline
- [Pre-Switch Checks](/stc/en/relics/pre-switch-checks/) — the deploy guard this profile enables
- [Server Survivability](/stc/en/relics/server-survivability/) — what this profile does instead of waiting for a console
- [Nix Housekeeping](/stc/en/relics/nix-housekeeping/) — how the store and the journal stay bounded
- [Schematic: aws-ami](/stc/en/schematics/aws-ami/) — a complete production example using this profile
