## Feature Plan: a persistent-state manifest (#64)

**Type:** Architectural — new relic (option declaration) populated by existing
relics

**Goal:** `nix eval .#nixosConfigurations.<host>.config.stc.relics.state.paths`
lists every piece of persistent state STC's enabled relics create, with what it
is and what kind of data it holds — so backup and impermanence lists can be
written without reading relic source.

**Why:** impermanence demands an exhaustive state inventory from the consumer,
while STC's own relics (crowdsec `dataDir`, Traefik's ACME material,
Vaultwarden's database) document theirs nowhere (#64).

### User decisions (2026-10-24)

- Namespace `stc.relics.state.paths`, declared by `relics/nixos/state.nix` —
  not the issue's `stc.state.paths`: the two-root rule in CLAUDE.md stands.
- Lot order #64 → #60 → #63, so the SMART relic populates the manifest from
  birth.

### Audit (2026-10-24, every file under `relics/nixos/`)

| Relic | State | Kind |
|---|---|---|
| `docker/traefik` | `<dataDir>/acme.json` (ACME account key, cert keys) | credentials |
| `docker/traefik` | `<dataDir>/logs` (read by CrowdSec) | log |
| `docker/crowdsec` | `<dataDir>/data` (LAPI database, decisions) | data |
| `docker/crowdsec` | `<dataDir>/etc` (LAPI / CAPI credentials, hub state) | credentials |
| `traefik` | `/var/lib/traefik` (ACME, logs) | credentials |
| `vaultwarden` | `/var/lib/vaultwarden` | data |
| `vaultwarden` | `/var/backup/vaultwarden` (when `backup`) | data |
| `hardening/ssh` | each `services.openssh.hostKeys` path | credentials |
| `zfs` | `/var/log/zed.debug.log` | log |

No persistent state: amd-gpu, aws, boot, impermanence (it *consumes* a list),
networking, nix-housekeeping, pipewire, plasma6, pre-switch-checks,
server-survivability, vm-variant, yubikey, docker/socket-proxy, docker/notify,
hardening/{kernel,network,filesystem,modules,scheduler} (scheduler's
`/var/cron` is regenerated from the store at every boot).

### Global Constraints

- Descriptive only: nothing reads the manifest; it cannot break a build.
- Entries appear only when the relic that owns them is enabled, and follow
  its options (`dataDir`, `hostKeys`), never a hard-coded copy.
- Each populating relic imports `state.nix` so it stays usable on its own.
- Wiring the manifest into impermanence is out of scope (issue says so).

### Review Focus

- Audit completeness: a relic with state and no entry, or an entry that is not
  state.
- The proving checks the manifest against reality, not against itself.

### Affected Files

- `relics/nixos/state.nix` (new), `relics/default.nix`
- `relics/nixos/{docker/traefik,docker/crowdsec,traefik,vaultwarden,hardening/ssh,zfs}.nix`
- `provings/docker-server.nix`
- `docs/src/content/docs/{en,fr}/reference/state-manifest.md` (new),
  `{en,fr}/relics/index.md`, and the populating relics' pages

### Atomic Steps

#### Step 1: plan + ledger
#### Step 2: `state.nix`, registered
#### Step 3: populated by the six relics
#### Step 4: proving — every manifest path exists on `machine`; crowdsec's
entries absent on `nocrowdsec`
#### Step 5: docs EN + FR

### Quality Gates

- `just ci` green.
- `just test` green.
- `nix eval` of the three schematics' `drvPath`; manifest evaluates on each.
- Consumer `gfriloux/nixos`: three hosts evaluate with `--override-input stc`,
  and their manifests are read back.
- One fresh-context review at branch close.
