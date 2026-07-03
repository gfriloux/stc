# The Rites
# Sacred library functions, utilities, and shared patterns.
# These are the incantations that make the other parts work.
# Do not question the Rites. Trust in the process.
#
# Also declares non-standard flake outputs (homeModules) so multiple
# sections (relics, cogitator) can contribute to them freely.
{
  lib,
  config,
  inputs,
  withSystem,
  ...
}: {
  options.flake.homeModules = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.unspecified;
    default = {};
    description = "Home Manager modules exposed by STC.";
  };

  config.flake.lib = {
    layouts = {
      zfs-local-vm = import ../forge/layouts/zfs-local-vm.nix;
    };
    docker = import ../relics/nixos/docker/_lib.nix;

    # Purity Seals — per-system CI check builders. Code lives in
    # forge/purity-seals/; rites exposes it under stc.lib, exactly as it does
    # for layouts. Per-system because the seals need a resolved `pkgs`.
    puritySeals =
      lib.genAttrs config.systems
      (system:
        withSystem system ({pkgs, ...}:
          import ../forge/purity-seals/seals.nix {
            inherit pkgs;
            # allowUnfree, scoped to the terraform seal only (Terraform is BSL).
            pkgs-unfree = import inputs.nixpkgs {
              inherit system;
              config.allowUnfree = true;
            };
          }));
  };
}
