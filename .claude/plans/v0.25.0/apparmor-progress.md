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
