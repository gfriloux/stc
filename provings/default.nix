# The Provings — STC's internal nixosTest suite.
#
# Provings verify *behaviour*: each boots a VM with a cogitator enabled and
# asserts it does what it claims. They are internal QA, not a consumer API.
#
# Exposed under legacyPackages.<system>.provings.*, which `nix flake check`
# deliberately skips — so provings are NOT part of the `just ci` gate. Run them
# by hand with `just test`. Linux only (VM tests are meaningless on Darwin).
#
# Builder: pkgs.testers.runNixOSTest. `self` is threaded in so the test node can
# import the real flake module (self.nixosModules.cogitator-*).
{
  self,
  inputs,
  lib,
  ...
}: {
  perSystem = {
    pkgs,
    system,
    ...
  }: let
    # Steam is unfree, and the `pkgs` flake-parts hands us does not allow it, so
    # the gaming proving cannot be built from it. The two ways of fixing that
    # from inside the test are both closed, measured:
    #
    #   - `nixpkgs.config.allowUnfree = true` in the node
    #       → error: nixpkgs.config is set to read-only
    #   - `node.pkgs = <instance>`
    #       → error: node.pkgs is defined multiple times
    #         (runNixOSTest defines it itself)
    #
    # So the instance has to be the one building the test. Scoped to the single
    # registry line that needs it, exactly as forge/default.nix does for
    # Terraform's BSL licence — the point is that no other proving, and nothing
    # else in the flake, gains the right to pull an unfree package in silently.
    pkgs-unfree = import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
  in
    lib.optionalAttrs (lib.elem system ["x86_64-linux" "aarch64-linux"]) {
      legacyPackages.provings = {
        hardening = pkgs.testers.runNixOSTest (import ./hardening.nix {inherit self;});
        docker-server = pkgs.testers.runNixOSTest (import ./docker-server.nix {inherit self;});
        workstation = pkgs.testers.runNixOSTest (import ./workstation.nix {inherit self;});
        vm = pkgs.testers.runNixOSTest (import ./vm.nix {inherit self;});
        plasma = pkgs.testers.runNixOSTest (import ./plasma.nix {inherit self;});
        dreadnought = pkgs.testers.runNixOSTest (import ./dreadnought.nix {inherit self;});
        sarcophagus-kvm = pkgs.testers.runNixOSTest (import ./sarcophagus-kvm.nix {inherit self;});
        sarcophagus-aws = pkgs.testers.runNixOSTest (import ./sarcophagus-aws.nix {inherit self;});
        # These two provings take `inputs` as well as `self`, and the other nine
        # do not. The reason is structural
        # rather than stylistic: Home Manager's NixOS module lives in an input,
        # and `self.homeModules.*` alone cannot attach a home configuration to a
        # test node — the node has to import
        # `inputs.home-manager.nixosModules.home-manager` first. The two
        # signatures therefore coexist on purpose; do not "harmonise" the other
        # nine onto a parameter they have no use for.
        enginseer = pkgs.testers.runNixOSTest (import ./enginseer.nix {inherit self inputs;});
        home-desktop = pkgs.testers.runNixOSTest (import ./home-desktop.nix {inherit self inputs;});
        # The only line built from pkgs-unfree — see the comment on that instance.
        gaming = pkgs-unfree.testers.runNixOSTest (import ./gaming.nix {inherit self;});
      };
    };
}
