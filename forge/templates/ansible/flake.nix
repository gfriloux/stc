{
  description = "Ansible project — multi-version shell + CI checks";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    stc = {
      url = "github:gfriloux/stc";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    flake-parts,
    stc,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      perSystem = {system, ...}: let
        inherit (stc.inputs.nix-checks.lib.${system}) checks;
      in {
        checks = {
          nix = checks.nix ./.;
          gitleaks = checks.gitleaks ./.;
          ansible = checks.ansible ./.;
          shell = checks.shell ./.;
        };

        devShells.default = stc.devShells.${system}.ansible;
      };
    };
}
