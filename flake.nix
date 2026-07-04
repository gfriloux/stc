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
      inputs.home-manager.follows = "home-manager";
    };

    television-ssh = {
      url = "github:gfriloux/television-ssh-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

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

    # nixos-25.11 stable — used by forge/builders for tools not yet on unstable
    # (e.g. specific Terraform/Ansible versions requiring stable package sets).
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.11";

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
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      imports = [
        ./relics
        ./cogitator
        ./forge
        ./rites
        ./provings
      ];

      perSystem = {pkgs, ...}: {
        formatter = pkgs.alejandra;

        devShells.default = pkgs.mkShell {
          name = "stc-forge";
          packages = with pkgs; [
            alejandra
            deadnix
            git
            just
            nix-tree
            statix
          ];
          shellHook = ''
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
