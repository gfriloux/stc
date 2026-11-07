{
  description = ''
    STC — Standard Template Construct
    The sacred repository of the Adeptus Technicus.
    A Nix flake library of reusable modules and profiles
    for the discerning Techpriest.

    Praise the Omnissiah. May your modules evaluate without heresy.
  '';

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin = {
      url = "github:catppuccin/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    gitflow-toolkit = {
      url = "github:gfriloux/gitflow-toolkit-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Module-only flake, no inputs of its own.
    television-ssh.url = "github:gfriloux/television-ssh-flake";

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    plasma-manager = {
      url = "github:nix-community/plasma-manager/trunk";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # Frozen on purpose: nixos-25.11 is end-of-life, and kept only because it is
    # the last branch carrying ansible_2_16 and ansible_2_17, which the ansible
    # forge shell needs to manage legacy hosts (CentOS 7, Amazon Linux 2). Used
    # by that shell alone — nothing else in the flake may read it. See
    # forge/shells/ansible.nix.
    nixpkgs-ansible-legacy.url = "github:nixos/nixpkgs/nixos-25.11";

    # Declares the repo's own pre-commit hooks — see the perSystem block below.
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ansible-recap = {
      url = "github:gfriloux/ansible-recap";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      imports = [
        inputs.git-hooks.flakeModule
        ./relics
        ./cogitator
        ./forge
        ./rites
        ./provings
        ./docs/options.nix
      ];

      perSystem = {
        config,
        pkgs,
        ...
      }: {
        formatter = pkgs.alejandra;

        # STC's own pre-commit hooks — the fast seals only. `nix flake check`
        # stays out: it takes minutes since every proving node is a check, and CI
        # and `just ci` run it. The module also adds checks.pre-commit, so CI runs
        # these same hooks. The forge shells keep their own pre-commit.yaml: they
        # serve consumer repos, which need not use flake-parts.
        pre-commit.settings.hooks = {
          alejandra.enable = true;
          statix.enable = true;
          deadnix.enable = true;
          docs-parity = {
            enable = true;
            name = "docs-parity";
            entry = "bash scripts/check-docs-parity.sh";
            files = "^docs/src/content/docs/";
            pass_filenames = false;
          };
        };

        devShells.default = pkgs.mkShell {
          name = "stc-forge";
          packages = with pkgs; [
            alejandra
            deadnix
            git
            git-cliff
            just
            nix-tree
            statix
            # Same pinned pre-commit as the installed hook, for `pre-commit run`.
            config.pre-commit.settings.package
          ];
          # Rewrites .git/hooks/pre-commit on every shell entry, so the hook always
          # points into this shell's closure and survives a garbage collection.
          shellHook = ''
            ${config.pre-commit.installationScript}
            echo ""
            echo "  ██████ ████████  ██████"
            echo " ██         ██    ██"
            echo "  ██████    ██    ██"
            echo "       ██   ██    ██"
            echo " ██████     ██     ██████"
            echo ""
            echo "  Standard Template Construct"
            echo "  Welcome to the Forge, Techpriest."
            echo "  Praise the Omnissiah."
            echo ""
          '';
        };

        devShells.docs = pkgs.mkShell {
          name = "stc-docs";
          packages = with pkgs; [nodejs just];
          shellHook = ''
            echo ""
            echo "  STC — Documentation Scriptorium"
            echo "  Node.js $(node --version) ready."
            echo "  just docs-dev"
            echo ""
          '';
        };
      };
    };
}
