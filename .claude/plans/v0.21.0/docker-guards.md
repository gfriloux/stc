## Feature Plan: docker guards — public ports and raw socket mounts (#101)

**Type:** Architectural — new relic (`docker/guards.nix`), wired into a
cogitator

**Goal:** a container that publishes a port on every interface, or mounts the
raw Docker socket, makes the build print a warning that names it and the
remedy — unless it says why with an opt-out label.

**Why:** Docker's DNAT rules sit ahead of `networking.firewall`, so
`ports = ["3000:8080"]` is on the public Internet whatever the firewall says,
skipping Traefik, TLS and CrowdSec. A raw `docker.sock` mount is host root,
whatever the socket-proxy relic promises. Both are green builds today (#101,
from gfriloux/nixos#92 and #100).

### User decisions (2026-10-25)

- Lot v0.21.0 = #101 then #102.

### Measured premises (2026-10-25, consumer `gfriloux/nixos`)

- clochette: `crowdsec-manager` publishes on `100.124.91.99` (a Tailscale
  address: passes) and mounts `/run/docker.sock` raw. gfriloux/nixos#100
  settled that it legitimately needs the full API. **One warning expected**;
  the consumer adds the opt-out label.
- clochette and RogueLeader: the Traefik container publishes `80`/`443` on
  every interface, and `docker-socket-proxy` mounts the socket — both by
  design of the STC relics that declare them.
- exampleHost: no container.

### Design

- `stc.relics.docker.guards.enable`; `cogitator-docker-server` enables it at
  `mkDefault`.
- Checks over `virtualisation.oci-containers.containers`, only when the
  backend is docker:
  - **ports**: an entry with no host address (`"8080"`, `"3000:8080"`,
    `"3000:8080/tcp"`) or bound to `0.0.0.0` / `[::]`. A specific address
    passes.
  - **socket**: a volume whose host side is `/run/docker.sock` or
    `/var/run/docker.sock`, `:ro` or not.
- Opt-out labels, value = the reason: `stc.docker/public-ports`,
  `stc.docker/raw-docker-socket`.
- Exemptions computed from STC's own relics, not labels: `traefik`'s ports
  when `relics.docker.traefik` is on (it is the public entry point);
  `docker-socket-proxy`'s socket when `relics.docker.socketProxy` is on.
  Traefik's raw-socket fallback (proxy off) is **not** exempt: it is the
  bypass the guard exists to show; the consumer labels it if they mean it.
- Warnings now; a follow-up issue promotes them once the consumer is clean.

### Global Constraints

- Warnings only in this release; no build breaks.
- No change to any container definition STC declares (a label on STC's own
  containers would restart Traefik and the proxy on the next switch).

### Review Focus

- Port-string parsing: every Docker short-syntax form, IPv6 brackets,
  ranges, protocols.
- Exemptions cannot hide a consumer container.

### Affected Files

- `relics/nixos/docker/guards.nix` (new), `relics/default.nix`
- `cogitator/nixos/docker-server.nix`, `scripts/option-priorities.tsv`
- `provings/docker-server.nix`
- `docs/src/content/docs/{en,fr}/relics/docker.md`,
  `{en,fr}/relics/index.md`, `{en,fr}/cogitator/docker-server.md`

### Atomic Steps

#### Step 1: plan + ledger
#### Step 2: the relic, registered; cogitator wiring; seal
#### Step 3: proving — the booted node's warnings carry no guard message
while it runs labelled and STC containers; negative cases by eval
#### Step 4: docs EN + FR; follow-up issue

### Quality Gates

- `just ci` green; `just test` green.
- `nix eval` of the three schematics' `drvPath`.
- Consumer: clochette shows exactly the crowdsec-manager socket warning,
  RogueLeader and exampleHost none.
- One fresh-context review at branch close.
