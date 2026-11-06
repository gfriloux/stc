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
| `terraform` | `path` | `terraform fmt -check`, `tflint --recursive`, `trivy config` |
| `ansible` | `path` | `ansible-lint --offline --profile production --exclude=tests` |
| `shell` | `path` | `shellcheck` sur `*.sh`, `shfmt -d -s -i 2 -ci` |
| `markdown` | `{ path, args ? "" }` | `rumdl check` (exclusions de règles via `args`) |

:::note[Terraform est unfree]
Le seal `terraform` utilise une instance nixpkgs avec `allowUnfree = true`
(Terraform est sous licence BSL depuis la v1.6). C'est cadré au seul seal
terraform — les autres seals ne tirent jamais de paquets unfree.
:::

## Migrer depuis tfsec (v0.23.0)

:::caution[Changement cassant]
Depuis la v0.23.0, le seal `terraform` lance **Trivy** (`trivy config`) au lieu
de tfsec, qu'Aqua Security a déprécié à son profit. Un dépôt Terraform qui
passait le seal peut désormais échouer sans qu'une ligne ait changé :

- **`.tfsec/config.yml` (ou les règles personnalisées de `.tfsec/`) est
  ignoré.** Les exclusions qui y figurent ne s'appliquent plus, donc les
  constats qu'elles masquaient reviennent.
- **Les jeux de règles diffèrent.** Trivy peut relever des constats que tfsec ne
  relevait pas, sous ses propres identifiants (`AVD-AWS-0107`) et sévérités.

Les commentaires en ligne `# tfsec:ignore:<id>` continuent de fonctionner :
Trivy les respecte, avec ou sans `:exp:<date>` (mesuré sur
`aws-ec2-no-public-ingress-sgr`). Vérifiez tout ignore dont Trivy aurait pu
renommer ou retirer la règle.
:::

Pour migrer une liste d'exclusions de `.tfsec/config.yml`, déplacez les
identifiants dans un fichier `.trivyignore` à la racine de l'arbre analysé, un
par ligne. L'identifiant tfsec comme l'identifiant Trivy sont acceptés :

```text
# .trivyignore
aws-ec2-no-public-ingress-sgr
AVD-AWS-0107
```

Préférez un `# trivy:ignore:<id>` en ligne à côté de la ressource quand
l'exception est locale : la raison reste alors à côté du code qu'elle excuse. Le
shell `terraform` fournit `trivy` à la place de `tfsec`, donc `trivy config .`
reproduit le seal en local.

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
