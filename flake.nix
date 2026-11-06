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

    # Frozen on purpose: nixos-25.11 is end-of-life, and kept only because it is
    # the last branch carrying ansible_2_16 and ansible_2_17, which the ansible
    # forge shell needs to manage legacy hosts (CentOS 7, Amazon Linux 2). Used
    # by that shell alone — nothing else in the flake may read it. See
    # forge/shells/ansible.nix.
    nixpkgs-ansible-legacy.url = "github:nixos/nixpkgs/nixos-25.11";

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
            git-cliff
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
