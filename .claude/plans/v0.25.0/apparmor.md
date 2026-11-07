## Maintenance Plan: AppArmor relic, docker containers confined (#32)

**Type:** Architectural — new relic (`stc.relics.hardening.apparmor`).

**Goal:** a hardening relic that turns AppArmor on and makes Docker actually
confine every container with its `docker-default` profile on NixOS, which
stock NixOS does not do even with `security.apparmor.enable = true`.

**Why:** #32 asks for Mandatory Access Control (CIS 1.6.x; ANSSI-BP-028 R37
and R45, both *enhanced*). On NixOS, distro profiles assume FHS paths, so a
general MAC rollout is out of reach. The measurable win is the container
boundary: Docker ships a profile for every container, and on NixOS it
silently does not apply it.

**Architecture:** one relic file, `relics/nixos/hardening/apparmor.nix`, like
the other eight hardening relics. It writes `security.apparmor.*` and, only
when `virtualisation.docker.enable`, the three things Docker needs to load
`docker-default`. Imported by `cogitator-hardening`, **not** enabled by it.
No new DESIGN.md boundary.

### Measured premises (2026-11-07, locked nixpkgs, VM spike)

Spike: `nixosTest`, `security.apparmor.enable` + `virtualisation.docker`, a
busybox image from `dockerTools.buildImage`, `docker run`.

- **Stock NixOS does not confine containers.** `docker inspect` reports
  `AppArmorProfile = docker-default`, `docker info` lists `name=apparmor`,
  but `/proc/1/attr/current` in the container reads `unconfined` and
  `aa-status` says "No policy loaded into the kernel". dockerd logs nothing.
- **Cause:** vendored containerd `pkg/apparmor/apparmor_linux.go:38`,
  `hostSupports()` requires `os.Stat("/sbin/apparmor_parser")` — an FHS path
  absent on NixOS — so moby's `defaultAppArmorProfileSupported()` is false and
  the profile is never loaded.
- With `/sbin/apparmor_parser` (tmpfiles symlink) and `apparmor-parser` in
  `virtualisation.docker.extraPackages`, dockerd tries and fails:
  `Failed to find declaration for: @{HOMEDIRS}` — the generated profile
  includes `<abstractions/base>` (NixOS provides it, and it uses
  `@{HOMEDIRS}`) but includes `<tunables/global>` only if
  `/etc/apparmor.d/tunables/global` exists (`macroExists`), and NixOS does not
  ship it. `docker run` then **fails** (HTTP 500), it does not fall back.
- Adding `security.apparmor.includes."tunables/global"` (an `include` of
  `apparmor-profiles`' file) and `security.apparmor.packages =
  [ pkgs.apparmor-profiles ]` (include path for `<tunables/home>` …):
  `docker-default` loads, the container's PID 1 is `docker-default (enforce)`,
  `aa-status`: 1 profile, 1 process in enforce mode; reading
  `/proc/sysrq-trigger` from the container is denied.
- `security.apparmor.enable` adds `lsm=…,apparmor apparmor=1` to the kernel
  command line: takes effect at the next boot, not at `switch`.
- ANSSI-BP-028 v2 (ComplianceAsCode `controls/anssi.yml`): R37 "Using access
  control features" (MAC, enhanced); R45 "Enable AppArmor security profiles"
  (all profiles enabled by default, enhanced); R46 SELinux targeted (high).

### User decisions (2026-11-07)

- Scope **A**: AppArmor on + Docker's `docker-default` working. No hand-written
  profile for `sshd` (spawns user shells, near-unconfined profile, lockout
  risk) nor for the containerised traefik/socket-proxy/crowdsec (a host
  profile does not apply inside a container).
- **Opt-in**: imported by `cogitator-hardening`, `enable` stays `false`
  everywhere. Enabling by default is a later release, like the docker guards.
- STC follows ANSSI first, but a gap ANSSI leaves may be closed with another
  standard (CIS here).

### Global Constraints

- No consumer sees a change: nothing enables the relic. Witness drvPaths of
  `schematics/local-vm` qcow2 and `schematics/aws-ami` awsImage unchanged.
- `docker-default` is Docker's, always `enforce`; `complain` (the issue's
  default) does not apply to it. A container opts out with
  `--security-opt apparmor=unconfined` (OCI: `extraOptions`).
- The Docker part is gated on `config.virtualisation.docker.enable`; a host
  without Docker gets AppArmor alone.

### Review Focus

- The `/sbin/apparmor_parser` symlink: an FHS path created on NixOS. Must not
  clash with an existing `/sbin` and must survive impermanence (tmpfiles, so
  recreated at every boot).
- `tunables/global` from `apparmor-profiles` pulling in rules that change what
  NixOS's own policies (nixpkgs modules with `security.apparmor.policies`)
  resolve.
- The proving discriminating STC from upstream: a node with
  `security.apparmor.enable` + Docker and **without** the relic must show the
  container `unconfined`.

### Affected Files

- `relics/nixos/hardening/apparmor.nix` (new), `relics/default.nix`,
  `cogitator/nixos/hardening.nix` (import only)
- `provings/apparmor.nix` (new), `provings/default.nix`
- `docs/src/content/docs/{en,fr}/relics/hardening.mdx`, `relics/index.md`,
  `cogitator/hardening.mdx`, `reference/anssi-bp-028.md`
- `docs/src/options/{en,fr}/relics-nixos-hardening-apparmor.md` (generated)

### Atomic Steps

#### Step 1: The relic and its documentation

**Description:** `relics/nixos/hardening/apparmor.nix` declares
`stc.relics.hardening.apparmor.enable` (`mkEnableOption`). `config = mkIf
cfg.enable (mkMerge [ … ])`:
- `security.apparmor.enable = true`;
- `mkIf config.virtualisation.docker.enable`: the tmpfiles rule
  `L+ /sbin/apparmor_parser - - - - ${pkgs.apparmor-parser}/bin/apparmor_parser`,
  `virtualisation.docker.extraPackages = [ pkgs.apparmor-parser ]`,
  `security.apparmor.packages = [ pkgs.apparmor-profiles ]`,
  `security.apparmor.includes."tunables/global"`.
Comments carry the measured cause (file:line in containerd). Registered as
`relics-hardening-apparmor`; imported by `cogitator-hardening`, not enabled.
Docs in the same commit (structural change): `## AppArmor` section in
`relics/hardening.mdx` (EN/FR) with `**Options:**` + generated fragment, what
it confines and what it does not (no host profiles, FHS vs `/nix/store`,
SELinux not on NixOS), the reboot note, the opt-out; `relics/index.md` and
`cogitator/hardening.mdx` (EN/FR) mention it; `just options-doc`.

**Files changed:** relic, `relics/default.nix`, `cogitator/nixos/hardening.nix`,
the doc pages above, `docs/src/options/**`

**Verification command(s):**
```bash
nix flake check --no-write-lock-file          # incl. checks.options-doc coverage
nix develop .#docs --command bash -c 'cd docs && npm run build'
bash scripts/check-docs-parity.sh
```

**Commit message:** `feat(relics): add hardening.apparmor, confining docker containers`

---

#### Step 2: Proving

**Description:** `provings/apparmor.nix`, registered in `provings/default.nix`.
Busybox image from `dockerTools.buildImage` (no network). Nodes:
- `confined`: the relic + Docker. Asserts: `aa-status` lists `docker-default`
  in enforce; container PID 1 attr is `docker-default (enforce)`; an action
  the profile denies fails in a default container and succeeds in one run
  with `--security-opt apparmor=unconfined` (same capabilities) — the
  discriminating action is measured first (candidate: `mount -t tmpfs` with
  `--cap-add SYS_ADMIN`).
- `upstream`: `security.apparmor.enable` + Docker, **without** the relic.
  Asserts the container is `unconfined` — the gap the relic closes. If this
  ever turns `docker-default`, upstream fixed it and the relic's Docker part
  can go.

**Verification command(s):**
```bash
nix build .#legacyPackages.x86_64-linux.provings.apparmor --no-write-lock-file -L
nix flake check --no-write-lock-file          # eval-apparmor-* nodes
```

**Commit message:** `test(provings): apparmor confines docker containers`

---

#### Step 3: ANSSI fidelity page

**Description:** `reference/anssi-bp-028.md` (EN/FR) gains the AppArmor rows:
R37 🟡 (MAC through AppArmor, confining Docker containers only; opt-in),
R45 🟡 (profiles loaded are enforced, but NixOS ships few and STC writes no
host profile), R46 ⚪ (SELinux: no NixOS store labelling). Rule titles as in
the guide; the CIS 1.6.x reference noted as the origin of #32.

**Verification command(s):**
```bash
nix develop .#docs --command bash -c 'cd docs && npm run build'
bash scripts/check-docs-parity.sh
```

**Commit message:** `docs(reference): AppArmor in the ANSSI-BP-028 fidelity map`

### Quality Gates

- [ ] `nix flake check --all-systems --no-build --no-write-lock-file` and `nix flake check --no-write-lock-file` pass
- [ ] Schematic drvPaths unchanged (`--override-input stc path:$PWD` vs main)
- [ ] `just fmt-check lint`
- [ ] `nix build .#legacyPackages.x86_64-linux.provings.apparmor` passes; `just test` unaffected otherwise
- [ ] Docs build, parity, namespace grep
- [ ] One fresh-context review at branch close
- [ ] All commits atomic and signed
