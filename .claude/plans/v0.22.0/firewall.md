## Feature Plan: firewall baseline relic (#33)

**Type:** Architectural — new relic

**Goal:** `stc.relics.hardening.firewall.enable = true` turns "the NixOS
firewall is on" from an assumption into a checked claim, and logs refused
connections; `cogitator-hardening` turns it on.

**Why:** relics open their own ports (`traefik.nix`, `docker/traefik.nix`) but
nothing in STC states the default-deny policy, checks it is still in force, or
logs what it refuses (#33, CIS ~3.5.x, informative only).

**Architecture:** a thin relic over upstream `networking.firewall`: one
default, one guard. It owns no port list and no backend: ports stay with the
relics and the consumer, through `networking.firewall.allowedTCPPorts` /
`allowedUDPPorts` and upstream `openFirewall` options.

### Measured premises (2026-10-31, locked nixpkgs + one spike nixosTest)

- `networking.firewall.enable` defaults to `true`; `logRefusedConnections`
  defaults to **`false`** (the issue assumed otherwise); `rejectPackets`
  `false` (drop).
- Spike, two servers with `cogitator-hardening` (iptables, and
  `networking.nftables.enable = true`) and a client: on both backends, SSH 22
  reachable, a listener on 8080 unreachable from the client and reachable
  locally (lo is accepted), and with `logRefusedConnections = true` every
  refused SYN is in `journalctl -k` as `refused connection: … DPT=8080`, IPv4
  and IPv6 alike. Same prefix in both backends' source.
- Only TCP SYNs are logged: the refused UDP probe left no line
  (`logRefusedPackets` would log every packet; upstream calls it a debugging
  aid).
- A 200-port scan from the client added only a handful of lines. Not
  explained yet (kernel rate limit or the scan loop); the proving does not
  rely on counts, and the docs will not promise one line per attempt.
- ANSSI-BP-028 v2.0 has no host-firewall rule (it mentions iptables/nftables
  only in passing): out of its scope, like the scheduler relic.
- Every STC schematic and every `gfriloux/nixos` host has the firewall on,
  iptables backend; none of the consumer hosts imports `cogitator-hardening`.
- The docs show a non-existent option, `stc.relics.hardening.network.allowedTCPPorts`,
  in `cogitator/hardening.md`, `cogitator/vm.md`, `cogitator/docker-server.md`
  (EN + FR): copying it fails evaluation. Fixed here, since this relic is where
  the port convention gets written down.

### User decisions (2026-10-31, plan approved)

1. **Firewall off with the relic on: assertion** (recommended) or warning.
   Assertion: a host that disabled the NixOS firewall (its own nftables
   ruleset, a cloud security group only) and takes `cogitator-hardening`
   fails evaluation until it sets `stc.relics.hardening.firewall.enable =
   false`. Same shape as the #40 `/var/tmp` assertion.
2. **No SSH rate-limit option** (recommended). sshd's `PerSourcePenalties`
   (ssh relic) already throttles at the application layer; a firewall rate
   limit needs one rule set per backend (`extraCommands` vs
   `extraInputRules`) for the same effect.

### Options

```nix
stc.relics.hardening.firewall = {
  enable = lib.mkEnableOption "the NixOS firewall as a checked default-deny baseline, with refused connections logged";
};
```

Config under `lib.mkIf cfg.enable`:

- `networking.firewall.logRefusedConnections = cfg.logRefusedConnections;` at
  normal priority, from an STC option (default true) — see the ledger, step 2
  (nixpkgs' installation-device profile holds a `mkDefault false`)
- assertion `config.networking.firewall.enable`,
  message naming the escape `stc.relics.hardening.firewall.enable = false`.

### Global Constraints

- Canonical namespace `stc.relics.hardening.firewall.*`; module `relics-hardening-firewall`.
- Backend-neutral: nothing that works on iptables only or nftables only.
- No port list in the relic.
- Schematics local-vm, aws-ami, dreadnought keep evaluating.

### Review Focus

- The guard firing on a consumer who runs their own ruleset — message must
  name the escape.
- Docker publishes ports ahead of `networking.firewall`: the docs must say this
  relic does not cover them and point to `docker.guards`.
- Log volume claims stay within what was measured.

### Affected Files

- `relics/nixos/hardening/firewall.nix` (new), `relics/default.nix`
- `cogitator/nixos/hardening.nix`, `cogitator/default.nix` (comment)
- `scripts/option-priorities.tsv`
- `provings/hardening.nix` (a `client` node)
- docs EN + FR: `relics/hardening.md`, `relics/index.md`,
  `cogitator/hardening.md`, `cogitator/vm.md`, `cogitator/docker-server.md`,
  `cogitator/index.md`, `reference/anssi-bp-028.md`,
  `reference/overridable-defaults.md`, `provings/index.md`, README

### Atomic Steps

#### Step 1: plan + ledger
#### Step 2: the relic, registered, in `cogitator-hardening` (mkDefault), seal rows

Produces `stc.relics.hardening.firewall.enable` (bool, false). Verification:
`nix-instantiate --eval` on a minimal nixosSystem with the suite — default:
`logRefusedConnections = true`, no failed assertion; `networking.firewall.enable
= false` → the guard fires; plus relic off → silent; `just ci`.

Commit: `feat(relics-hardening-firewall): checked default-deny firewall with refused connections logged (#33)`

#### Step 3: proving

Consumes the relic through `stc.cogitator.hardening.enable`. `provings/hardening.nix`
gains a `client` node and a listener on 8080 on `machine`: firewall unit
active; client reaches 22; client cannot reach 8080 while `machine` reaches it
on lo (so the listener is up and the refusal is the firewall's); `journalctl -k`
holds `refused connection:` with `DPT=8080`. The log line is what discriminates
STC (upstream logs nothing); the refusal itself is upstream's.

Commit: `test(provings): hardening refuses and logs a probe to a closed port (#33)`

#### Step 4: docs EN + FR

`relics/hardening.md` Firewall section (what it adds, the port convention for
relics and consumers, `openFirewall`, Docker caveat, TCP-SYN-only logging,
rate limiting left to sshd); the three wrong `network.allowedTCPPorts`
examples → `networking.firewall.allowedTCPPorts`; counts seven → eight; ANSSI
"out of scope" section; overridable-defaults row; provings index.

Commit: `docs: firewall relic, port convention, and the non-existent network.allowedTCPPorts fixed (en, fr) (#33)`

### Quality Gates

- `just ci` green (seal included).
- Provings `hardening`, `sarcophagus-kvm`, `dreadnought` green (the suite now
  carries one more relic).
- `nix eval` of the three schematics' `drvPath`.
- Consumer `gfriloux/nixos`: four hosts and the home evaluate.
- One fresh-context review at branch close.
