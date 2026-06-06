# The Forge
# Builders, disk layouts, dev shells, and project templates.
# Here, raw Nix is hammered into functional artifacts.
{inputs, ...}: {
  flake.templates = {
    ansible = {
      path = ./templates/ansible;
      description = "Ansible project — multi-version shell (2.16, 2.17, latest) + CI checks";
    };
    terraform = {
      path = ./templates/terraform;
      description = "Terraform module — shell with terragrunt + terraform-docs + CI checks";
    };
    mdbook = {
      path = ./templates/mdbook;
      description = "mdBook documentation site — shell + markdown lint + CI checks";
    };
    mkdocs = {
      path = ./templates/mkdocs;
      description = "mkdocs documentation site — pipenv-based shell + markdown lint + CI checks";
    };
    zensical = {
      path = ./templates/zensical;
      description = "Zensical documentation site — pipenv-based shell + markdown lint + CI checks";
    };
  };

  perSystem = {
    system,
    pkgs,
    ...
  }: let
    preCommitConfig = ./shells/pre-commit.yaml;

    pkgs-stable = import inputs.nixpkgs-stable {inherit system;};

    pkgs-ansible = import inputs.nixpkgs {
      inherit system;
      overlays = [inputs.ansible-recap.overlays.default];
    };

    # Terraform has been BSL-licensed since v1.6. Unfree must be explicitly
    # allowed for the shell that uses it. Scope it narrowly to avoid
    # accidentally allowing other unfree packages across the board.
    pkgs-unfree = import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
  in {
    devShells = {
      ansible = import ./shells/ansible.nix {
        pkgs = pkgs-ansible;
        inherit pkgs-stable preCommitConfig;
      };
      terraform = import ./shells/terraform.nix {
        pkgs = pkgs-unfree;
        inherit preCommitConfig;
      };
      mdbook = import ./shells/mdbook.nix {inherit pkgs preCommitConfig;};
      mkdocs = import ./shells/mkdocs.nix {inherit pkgs preCommitConfig;};
      zensical = import ./shells/zensical.nix {inherit pkgs preCommitConfig;};
      vm = import ./shells/vm.nix {inherit pkgs preCommitConfig;};
      nixos = import ./shells/nixos.nix {inherit pkgs preCommitConfig;};
    };
  };
}
