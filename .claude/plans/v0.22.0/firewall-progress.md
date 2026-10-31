# Ledger — plan: .claude/plans/v0.22.0/firewall.md

Pre-flight: issue #33 read; upstream `nixos/modules/services/networking/firewall{,-iptables,-nftables}.nix`
read on the locked nixpkgs; one spike nixosTest (iptables and nftables
servers with `cogitator-hardening`, plus a client) — results in the plan's
measured premises. STC schematics and `gfriloux/nixos` hosts: firewall on,
iptables, no consumer host imports `cogitator-hardening`.

Pre-flight: step 3 consumes `stc.relics.hardening.firewall.enable` as step 2
produces it, through `stc.cogitator.hardening.enable` already set by the
proving node.

Step 1: Ruling: **`logRefusedPackets` stays off.** It logs every refused
packet, UDP and broadcasts included; upstream presents it as a debugging aid.
The SYN log answers "who knocked on a closed port".

Step 1: Ruling: **`rejectPackets` stays off** (drop, upstream default):
rejecting makes scanning faster, and nothing in the issue asks for it.

Step 1: plan approved by the user: assertion (not warning) when the firewall
is off; no SSH rate-limit option. Asked first which backend is in use:
iptables everywhere (schematics and consumer hosts), relic stays neutral.

Step 2: `relics/nixos/hardening/firewall.nix`, registered as
`relics-hardening-firewall`, in `cogitator-hardening` at mkDefault.
Ruling (forced by the seal): **`logRefusedConnections` is an STC option
(default true) written at normal priority**, not a mkDefault on the upstream
option. The seal found `networking.firewall.logRefusedConnections = mkDefault
false` in nixpkgs' `profiles/installation-device.nix`: two disagreeing
mkDefaults are a build error, e.g. an installer ISO with the hardening suite.
Measured by `nix-instantiate --eval` on a minimal nixosSystem with the suite:
default → firewall on, logging on, no failed assertion; installation-device
profile imported → evaluates, logging on; `firewall.logRefusedConnections =
false` → logging off; `networking.firewall.enable = false` → the assertion
fires; plus relic off → silent; `networking.nftables.enable = true` →
unchanged. Seal: hardening cogitator 7 → 8; `just ci` green (26 files, 55
options).

Step 3: `provings/hardening.nix` gains a `client` node and a netcat listener
on 8080 on `machine`. Green on the first run: firewall unit active, listener
answers on lo, client reaches 22, client refused on 8080, `refused
connection:` with `DPT=8080` in `journalctl -k`.

Step 4: docs EN + FR — relics/hardening Firewall section (options, assertion,
logging scope, the logRefusedConnections note, port convention and
openFirewall, own-ruleset escape, Docker and rate-limit limits; counts seven →
eight; usage example), the non-existent `stc.relics.hardening.network.allowedTCPPorts`
replaced in cogitator/hardening, vm (dropped: openssh opens 22) and
docker-server; relics/index, cogitator/index, profile pages, overridable-defaults
profiles row, architecture, README; ANSSI out-of-scope section; provings index
row. Ruling: the "twenty VM boots" paragraph (deferred since #40) recounted
by evaluation — node names from `provings.<p>.nodes`, booted nodes from the
test scripts: 23 boots (hardening now two nodes; plasma and home-desktop were
already miscounted). Parity OK.

Gates: provings hardening, sarcophagus-kvm, dreadnought green; just ci green;
local-vm, aws-ami, dreadnought drvPath OK; consumer RogueLeader, clochette,
exampleHost, skitarii and kuri@exampleHost evaluate.

Closing review (fresh context): no Critical.
- I1 taken: cogitator/hardening still listed a phantom `allowedTCPPorts` among
  "individual relic options" (EN + FR); replaced by real ones.
- I2 taken: ferm, shorewall and shorewall6 set `systemd.services.firewall.enable
  = false` and leave `networking.firewall.enable` true (ferm's default ruleset
  allows everything) — the relic would vouch for nothing. Second assertion,
  measured: `services.ferm.enable = true` → fires; with the relic off →
  silent; installation-device profile → still evaluates.
- M3 firewalld translates the option into its own LogDenied: comment and docs
  scoped to iptables/nftables. M4 overridable-defaults "set through an STC
  option" gains the firewall case. M5 the v0.18.0 table row back to the six
  sub-relics of the time, with audit and firewall named as mkDefault from the
  start (audit had inherited the same error in #31). M6 FR "rejette" → "ignore
  (DROP)". M7 "a plain `false`". M8 "spike" jargon removed. M9 index order. M10
  plan Options block aligned with the code.
