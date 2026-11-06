---
title: Purity Seals
description: STC's CI check builders — seal a source tree as inspected and free of heresy.
---

Purity Seals are STC's CI check builders. A passing seal stamps a source tree as
inspected and free of heresy: no dead Nix, no antipatterns, no leaked secrets,
clean formatting. Each seal is a pure Nix function from a source path to a check
derivation, exposed per system under `stc.lib.puritySeals`.

The builders live in `forge/purity-seals/`; STC exposes them through `stc.lib`,
exactly as it does for layouts. Every forge template wires its `checks` output to
this API — it is STC's public contract, not a private input.

## API

```text
stc.lib.puritySeals.<system> = {
  nix       = path: derivation;
  gitleaks  = path: derivation;
  terraform = path: derivation;
  ansible   = path: derivation;
  shell     = path: derivation;
  markdown  = { path, args ? "" }: derivation;
};
```

## Seals

| Seal | Signature | What it runs |
|------|-----------|--------------|
| `nix` | `path` | `deadnix --fail`, `statix check`, `alejandra --check` |
| `gitleaks` | `path` | `gitleaks dir --no-banner --verbose --redact` |
| `terraform` | `path` | `terraform fmt -check`, `tflint --recursive`, `trivy config` |
| `ansible` | `path` | `ansible-lint --offline --profile production --exclude=tests` |
| `shell` | `path` | `shellcheck` over `*.sh`, `shfmt -d -s -i 2 -ci` |
| `markdown` | `{ path, args ? "" }` | `rumdl check` (pass rule excludes via `args`) |

:::note[Terraform is unfree]
The `terraform` seal uses a nixpkgs instance with `allowUnfree = true` (Terraform
is BSL-licensed since v1.6). This is scoped to the terraform seal only — the other
seals never pull in unfree packages.
:::

## Migrating from tfsec (v0.23.0)

:::caution[Breaking change]
Since v0.23.0 the `terraform` seal runs **Trivy** (`trivy config`) instead of
tfsec, which Aqua Security deprecated in its favour. A Terraform repository that
passed the seal before can fail it without changing a line:

- **`.tfsec/config.yml` (or `.tfsec/` custom checks) is ignored.** Exclusions
  listed there no longer apply, so the findings they hid come back.
- **The rule sets differ.** Trivy can report findings tfsec did not, under its
  own IDs (`AVD-AWS-0107`) and severities.

Inline `# tfsec:ignore:<id>` comments keep working: Trivy honours them, with or
without `:exp:<date>` (measured on `aws-ec2-no-public-ingress-sgr`). Check any
ignore whose rule Trivy may have renamed or dropped.
:::

To migrate a `.tfsec/config.yml` exclusion list, move the IDs into a
`.trivyignore` file at the root of the scanned tree, one per line. Both the
tfsec ID and the Trivy ID are accepted:

```text
# .trivyignore
aws-ec2-no-public-ingress-sgr
AVD-AWS-0107
```

Prefer an inline `# trivy:ignore:<id>` next to the resource when the exception
is local: the reason then sits next to the code it excuses. The `terraform`
dev shell ships `trivy` instead of `tfsec`, so `trivy config .` reproduces the
seal locally.

## Usage in a flake

Any flake that takes STC as an input can seal itself. Wire the seals into the
standard `checks` output so `nix flake check` runs them:

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    stc.url = "github:gfriloux/stc";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs @ { flake-parts, stc, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];

      perSystem = { system, ... }: let
        checks = stc.lib.puritySeals.${system};
      in {
        checks = {
          nix = checks.nix ./.;
          gitleaks = checks.gitleaks ./.;
          markdown = checks.markdown {
            path = ./.;
            args = "-d MD013,MD033";
          };
        };
      };
    };
}
```

Then:

```bash
nix flake check
```

## See Also

- [Forge — Templates](/stc/en/forge/templates/) — every template ships with seals wired in
- [Forge — Shells](/stc/en/forge/shells/) — the matching dev shells carry the same linters
