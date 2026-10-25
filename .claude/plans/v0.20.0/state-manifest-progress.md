# Ledger — plan: .claude/plans/v0.20.0/state-manifest.md

Pre-flight: every file under `relics/nixos/` read for paths it creates
(tmpfiles, volumes, upstream services it enables) before the plan was written.

Step 1: Ruling: **`kind` gains `log`** beside the issue's `data | cache |
credentials`. Traefik's `<dataDir>/logs` and ZED's debug log are neither data
to restore nor a cache to drop: CrowdSec reads the Traefik logs, and an
impermanence user needs to know they live outside `/var/log`. Cost if wrong:
one enum value to deprecate.

Step 1: Ruling: **relics only; `/var/lib/docker` is not declared.** Docker is
enabled by the docker-server *cogitator*, not a relic, and what it holds
(images, the consumer's volumes) belongs to the consumer's applications.

Step 1: Ruling: **SSH host keys come from `services.openssh.hostKeys`**, so a
consumer who moves or adds keys sees the real paths.

Step 3: populated by six relics, each importing `state.nix` and writing under
its own enable. Paths derive from options: docker relics' `dataDir`,
`services.traefik.dataDir`, `services.openssh.hostKeys` (entries are
`attrs`, so `type` is read with `?`). Measured by eval on the docker-server
proving: `machine` lists crowdsec + traefik entries, `nocrowdsec` only
traefik's.

Step 4: two discriminating checks against reality. docker-server: every
manifest path exists on the booted node, crowdsec's are present on `machine`
and absent on `nocrowdsec`. hardening: the manifest's host keys equal the
`hostkey` lines of `sshd -T` and are non-empty files — the manifest cannot
drift from what sshd loads. `hardening`'s testScript became
`{nodes, ...}: ''…''` to read the evaluated manifest.

Step 5: Ruling: **the doc lives in `reference/state-manifest.md`** (the issue
asks for `docs/*/reference/`), with the per-relic table there and one row in
the relics index; the six relic pages are not each edited — one table is
easier to keep true than six scattered lines.

Closing review (fresh context): no Critical. **Important, all taken:**
- **Audit gap:** docker/traefik mounts `<dataDir>/conf/traefik_dynamic.yml`,
  which the consumer writes by hand when `dynamicConfigFile` is unset — real
  state nothing regenerates. Now listed (`file`, `data`). The proving first
  went red on it (`test -e` failed: nothing creates it on a fresh node), which
  confirmed the gap; it now asserts the entry is *listed* and exempts it from
  the existence check.
- **Vaultwarden path was hard-coded:** nixpkgs keeps `StateDirectory =
  "bitwarden_rs"` for `stateVersion < 24.11`. Both the manifest entry and the
  pre-existing impermanence persistence entry now read
  `systemd.services.vaultwarden.serviceConfig.StateDirectory`. Measured by
  eval: 25.05 → `/var/lib/vaultwarden`, 24.05 → `/var/lib/bitwarden_rs`. For
  an old-stateVersion impermanence host this is a bug fix (the real directory
  was not persisted); no consumer host uses the relic.
- **Impermanence recipe would fail:** files and directories were mixed, and
  feeding back paths impermanence already persists trips its duplicate
  assertion. Ruling: **`type = file | directory` added to the schema now**,
  while it costs nothing; the doc names what is already persisted and the
  recipe selects the Docker `dataDir` entries, split by type.
Minors taken: native Traefik log paths follow `services.traefik.dataDir`
(older bug, now visible through the manifest); hardening proving compares
only `/etc/ssh/` entries against a raw (not lowercased) `sshd -T`;
`shlex.quote` on paths; scope stated as NixOS relics, home state (zen's
`~/.zen`) out of scope; `rsa_key.pem` called out in the doc. Not taken: ZED
log kept (harmless, M7); SDDM's `/var/lib/sddm` not listed (last session
only, nothing to restore).
