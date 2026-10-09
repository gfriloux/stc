# STC — Security Policy

## Reporting vulnerabilities

Open a private GitHub Security Advisory on this repository. Do not use public issues for vulnerability reports.

## Threat model and non-goals

### Password quality and account lockout

STC configures **no password policy and no account-lockout policy**. There is no
`pam_pwquality`, no `pam_faillock`, and no password expiration in any relic. This
is a decision, not an oversight.

**What removes the remote attack surface.** `relics.hardening.ssh` sets
`PasswordAuthentication = false` and `KbdInteractiveAuthentication = false`:
sshd accepts public keys only, so there is no remote password to guess. The
remaining remote budget is capped by `MaxAuthTries 3`, `LoginGraceTime 20` and
`PerSourcePenalties`.

**Why the PAM controls are a non-goal.** The schematics declare
`users.mutableUsers = false`. Passwords are therefore fixed at build time by the
consumer (`hashedPassword` / `hashedPasswordFile`) and `passwd` cannot change
them at runtime. `pam_pwquality` gates interactive password changes — on such a
system it has nothing to arbitrate. Likewise, expiring a password the user cannot
rotate without a rebuild turns an account policy into a deployment outage.
Password strength belongs to whoever generates the hash, and password rotation is
an operational rite, not a library option.

**Residual risk, stated plainly.** Local authentication paths — a TTY login, a
display-manager greeter, `sudo` — accept an unlimited number of attempts, and a
weak password set by the consumer is caught by nothing in STC. The threat model
for those paths is physical or console access, answered by disk encryption and
boot integrity (the consumer's disko layout and hardware), not by PAM. A consumer
who needs lockout on local login can set `security.pam` options in their own
flake; a dedicated relic would be a separate change.

## Dependency posture

STC depends on a mix of nix-community projects and personal flakes. This document is explicit about the trust level of each.

### Tier 1 — nix-community (high trust)

Maintained by the nix-community organisation with multiple maintainers and CI.

| Input | Repository |
|-------|-----------|
| `nixpkgs` | github:nixos/nixpkgs |
| `home-manager` | github:nix-community/home-manager |
| `disko` | github:nix-community/disko |
| `impermanence` | github:nix-community/impermanence |
| `sops-nix` | github:Mic92/sops-nix |
| `catppuccin` | github:catppuccin/nix |
| `plasma-manager` | github:nix-community/plasma-manager |

### Tier 2 — project owner (medium trust)

Flakes authored and maintained by the STC project owner. Source is auditable by project contributors.

| Input | Repository |
|-------|-----------|
| `gitflow-toolkit` | github:gfriloux/gitflow-toolkit-flake |
| `television-ssh` | github:gfriloux/television-ssh-flake |
| `ansible-recap` | github:gfriloux/ansible-recap |
| `nix-checks` | github:gfriloux/nix-checks |

### Tier 3 — third-party individual (lower trust)

Maintained by individual accounts outside nix-community or the project owner. These carry supply chain risk.

| Input | Repository | Risk |
|-------|-----------|------|
| `zen-browser` | github:0xc000022070/zen-browser-flake | Unofficial wrapper by an individual account. No official Zen Browser Nix package exists as of 2026. Monitor for ownership changes or unexpected commits. |

**Mitigation for `zen-browser`:** the flake is pinned in `flake.lock`. Updates only happen on explicit `nix flake update`. Review the diff before updating.

## Diamond dependencies

Two inputs (`gitflow-toolkit`, `television-ssh`) use `snowfall-lib`, which pulls `flake-utils-plus` at a pinned revision. This creates duplicate entries in the lock file (`flake-utils-plus`, `flake-compat`) that cannot be deduplicated via `.follows`.

This is a known limitation, not a security issue. The duplicated packages are build tools only and do not appear in any system closure.

## Supply chain checklist for contributors

When adding a new flake input:

1. Prefer `nix-community` or well-known organisations over individual accounts.
2. Add `inputs.nixpkgs.follows = "nixpkgs"` (and `home-manager.follows` where applicable).
3. Document the new dependency in this file under the appropriate trust tier.
4. If the dependency is Tier 3, note the specific risk and mitigation.

## devShell packages

The `devShells.default` shell installs `alejandra`, `statix`, `deadnix`, `just`, `git`, and `nix-tree` — all sourced from nixpkgs. No third-party binary downloads occur during dev environment setup.
