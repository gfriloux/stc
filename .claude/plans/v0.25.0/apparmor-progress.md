# Ledger — plan: .claude/plans/v0.25.0/apparmor.md

Pre-flight: step 2 consumes the relic of step 1 (`relics/nixos/hardening/apparmor.nix`,
option `stc.relics.hardening.apparmor.enable`); step 3 consumes nothing but the
measured premises. The spike that grounds the premises is not committed.
Step 1: Ruling: the hardening page says "nine relics", the cogitator shortcut
"the eight other than AppArmor" — the cogitator imports it without enabling it,
so "enables all eight" stays true and the ninth is named.
Step 1: complete (fmt-check + lint OK; nix flake check → 0 incl. options-doc
coverage of the new fragment; docs build 104 pages, parity OK; a nixosSystem
with cogitator-hardening + apparmor + docker evaluates — toplevel drvPath
rhddvq56…).
Step 1: committed ec8b7c6.
Step 2: Discriminating action measured on a spike (both nodes, CAP_SYS_ADMIN):
confined/default mount → "Permission denied", confined/unconfined → rc 0,
upstream/default → attr `unconfined`, mount rc 0. /proc/sysrq-trigger rejected
as a candidate: unconfined reads fail too (EIO), so it does not discriminate.
Step 2: Ruling: proving docs (coverage row, "thirteen of the fifteen", one
paragraph in the relic section) ride in the step 2 commit — they describe the
proving, not the relic.
Step 2: complete (proving passes, script 36 s; fmt-check + lint OK; nix flake
check "all checks passed!" with eval-apparmor-confined/-upstream; docs build
104 pages, parity OK).
Step 3: Ruling: R37/R45/R46 also added to the "Relevant rules" table, and the
rows live in their own `relics.hardening.apparmor` section (between audit and
firewall), like every other relic on the page.
Step 3: complete (docs build 104 pages, parity OK, #apparmor anchor present on
both language pages).
Gate: schematic drvPaths unchanged vs main (local-vm 6w83sj19…, aws-ami
6cfzl6gi…), measured before and after the review fixes.
Review (fresh context, branch close): MEDIUM — apparmor.service's ExecReload
runs aa-remove-unknown, which unloads docker-default (loaded at runtime by
dockerd, never under /etc/apparmor.d): running containers turned unconfined.
Measured on a spike: old container `unconfined` after `systemctl reload
apparmor`, new ones confined, `docker restart` re-confines.
Ruling (user): stub `profile docker-default {}` in /etc/apparmor.d via
security.apparmor.includes — names it for aa-remove-unknown, never loaded by
NixOS (only security.apparmor.policies are). Measured: after reload the running
container stays `docker-default (enforce)` and the mount is still denied (so
Docker's profile, not the empty stub). A restart of apparmor.service still
tears everything down (aa-teardown, source-read): documented, not fixed.
Review LOW, fixed: security.apparmor.packages = [apparmor-profiles] was
redundant (nixpkgs profiles.nix:6) — removed, parser.conf no longer has the
duplicate Include; brittle "1 processes are in enforce mode." assert dropped;
"per Docker's template" for the deny list; rootless Docker/Podman named as
not covered.
Review note, ruled: the FR R37/R45/R46 wording is in the "Sujet" column, a
paraphrase like every other row; the guide's exact FR text could not be
fetched, so no exact-title claim is made.
Review fixes: complete (proving 4 subtests pass, 37 s; fmt-check + lint 0;
flake check 0; docs 104 pages, parity OK; drvPaths unchanged).
