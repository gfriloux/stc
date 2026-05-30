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

    television-ssh = {
      url = "github:gfriloux/television-ssh-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence.url = "github:nix-community/impermanence";

    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.05";

    ansible-recap = {
      url = "github:gfriloux/ansible-recap";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-checks = {
      url = "github:gfriloux/nix-checks";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
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
      ];

      perSystem = { pkgs, ... }: {
        formatter = pkgs.alejandra;

        devShells.default = pkgs.mkShell {
          name = "stc-forge";
          packages = with pkgs; [
            alejandra
            deadnix
            git
            just
            nodejs
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
      };
    };
}
