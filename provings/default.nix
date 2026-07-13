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
  lib,
  ...
}: {
  perSystem = {
    pkgs,
    system,
    ...
  }:
    lib.optionalAttrs (lib.elem system ["x86_64-linux" "aarch64-linux"]) {
      legacyPackages.provings = {
        hardening = pkgs.testers.runNixOSTest (import ./hardening.nix {inherit self;});
        docker-server = pkgs.testers.runNixOSTest (import ./docker-server.nix {inherit self;});
      };
    };
}
