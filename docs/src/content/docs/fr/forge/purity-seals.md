---
title: Purity Seals
description: Les constructeurs de checks CI de STC — sceller un arbre source comme inspecté et exempt d'hérésie.
---

Les Purity Seals sont les constructeurs de checks CI de STC. Un seal qui passe
scelle un arbre source comme inspecté et exempt d'hérésie : pas de Nix mort, pas
d'antipatterns, pas de secrets fuités, formatage propre. Chaque seal est une
fonction Nix pure d'un chemin source vers une dérivation de check, exposée par
système sous `stc.lib.puritySeals`.

Les constructeurs vivent dans `forge/purity-seals/` ; STC les expose via
`stc.lib`, exactement comme pour les layouts. Chaque template de la Forge câble sa
sortie `checks` sur cette API — c'est le contrat public de STC, pas un input privé.

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

| Seal | Signature | Ce qu'il exécute |
|------|-----------|------------------|
| `nix` | `path` | `deadnix --fail`, `statix check`, `alejandra --check` |
| `gitleaks` | `path` | `gitleaks dir --no-banner --verbose --redact` |
| `terraform` | `path` | `terraform fmt -check`, `tflint --recursive`, `tfsec` |
| `ansible` | `path` | `ansible-lint --offline --profile production --exclude=tests` |
| `shell` | `path` | `shellcheck` sur `*.sh`, `shfmt -d -s -i 2 -ci` |
| `markdown` | `{ path, args ? "" }` | `rumdl check` (exclusions de règles via `args`) |

:::note[Terraform est unfree]
Le seal `terraform` utilise une instance nixpkgs avec `allowUnfree = true`
(Terraform est sous licence BSL depuis la v1.6). C'est cadré au seul seal
terraform — les autres seals ne tirent jamais de paquets unfree.
:::

## Utilisation dans un flake

Tout flake qui prend STC comme input peut se sceller lui-même. Câble les seals
dans la sortie standard `checks` pour que `nix flake check` les exécute :

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

Puis :

```bash
nix flake check
```

## Voir aussi

- [Forge — Templates](/stc/fr/forge/templates/) — chaque template embarque ses seals câblés
- [Forge — Shells](/stc/fr/forge/shells/) — les dev shells correspondants portent les mêmes linters
