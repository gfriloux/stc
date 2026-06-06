# The Rites
# Sacred library functions, utilities, and shared patterns.
# These are the incantations that make the other parts work.
# Do not question the Rites. Trust in the process.
#
# Also declares non-standard flake outputs (homeModules) so multiple
# sections (relics, cogitator) can contribute to them freely.
{lib, ...}: {
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
  };
}
