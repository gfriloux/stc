# Ledger — plan: .claude/plans/v0.21.0/docker-guards.md

Pre-flight: issue #101 and its comment read; consumer containers listed on
clochette, RogueLeader and exampleHost (ports, socket volumes, stc labels).

Step 1: Ruling: **exemptions come from the relics, not from labels on STC's
containers.** A label is part of the container definition: adding one to
Traefik and the proxy would restart both on every consumer's next switch,
for no behaviour change.

Step 1: Ruling: **Traefik's raw-socket fallback warns.** With the proxy off,
the Traefik relic mounts the socket itself. That is exactly a bypass of the
proxy; the consumer silences it with the label on `traefik`, which merges
into STC's definition.

Step 1: Ruling: **`--publish` in `extraOptions` and `--network=host` are out
of scope.** Host networking does not bypass the NixOS firewall (the host's
own stack serves the port); `-p` in extraOptions is not how oci-containers
declares ports. Documented as a limit.

Step 1: Finding: **the consumer imports the docker relics one by one**
(clochette and RogueLeader import `relics-docker-*`, not
`cogitator-docker-server`), so the cogitator wiring does not reach them: they
must import `relics-docker-guards` and enable it. Docs say so. Measured with
the relic added through `extendModules`: clochette warns exactly once
(`crowdsec-manager` mounts the raw socket), RogueLeader not at all — the plan's
prediction. Without it: `[]` on all three hosts.

Step 2: `relics/nixos/docker/guards.nix`, registered as
`relics-docker-guards`; `cogitator-docker-server` imports it and sets
`guards.enable = mkDefault true`; seal row for docker-server 6 → 7 mkDefault.
Port parsing measured by eval on twelve forms: bare container port, no
address, with protocol, `0.0.0.0`, `[::]`, `:80:80` → public;
`127.0.0.1` (with `/udp`), `[::1]`, a Tailscale address, `127.0.0.1::8080`
(random host port, loopback), an address with a port range → pass; a range
without address → public.

Step 3: `provings/docker-server.nix`: `machine` gains an unlabelled container
(public `8080:80/tcp`, loopback `127.0.0.1:9090:90`, raw socket `:ro`) and a
labelled one with the same bypasses; `nocrowdsec` declines the guards and
carries the unlabelled one. The script reads both nodes' evaluated warnings:
exactly the two messages for `stc-proving-exposed` on `machine`, none on
`nocrowdsec`. Green on the first run. Side effect: `just test` now prints
those two evaluation warnings while building — the proving's own fixture.

Step 4: docs: `relics/docker.md` "Docker Guards" section EN + FR (what warns,
exemptions, labels with reasons, limits, warning-then-assertion path),
relics index row, docker-server cogitator block, provings coverage row.

Closing review (fresh context): no Critical.
- **I1 taken.** The Traefik exemption covered the whole container, and
  `ports` is a list a consumer appends to: `traefik.ports = ["8081:8080"]`
  was silent. Now only the relic's own `80:80/tcp` and `443:443/tcp` are
  subtracted (duplicated from traefik.nix; a drift makes the proving's
  Traefik warn). Proving: `machine` appends `8081:8080` to `traefik` and
  expects its warning.
- Minor taken: any bracketed all-zero IPv6 (`[::0]`, `[0:0:…:0]`) is public
  (eval: `[::]`/`[::0]`/`[0:…:0]` true, `[::1]`/`[fd00::1]` false); a whole
  `/run` or `/var/run` mount counts as a socket mount; a warning when the
  guards are on but the backend is not docker; firewall wording narrowed to
  "whatever `allowedTCPPorts` says" (nftables `filterForward` does filter
  forwarded traffic); limits now name `-v`/`--mount` in extraOptions, a
  daemon-wide `ip`, and loopback binds before Docker 28.
- Minor taken, proving: a third node `noproxy`, never booted (its warnings
  are read at evaluation; the log shows no `noproxy #` line), proves the
  exemptions follow the relics: with the proxy off, Traefik's raw-socket
  fallback warns, and a consumer container named `docker-socket-proxy` warns.
- Minor not taken: unbracketed IPv6 loopback (`::1:80:80`) is flagged — a
  false positive on a form Docker accepts but nobody writes; the warning
  text stays generic rather than naming crowdsec-manager.
- Follow-up issue (promote to assertions): opened with the PR.
