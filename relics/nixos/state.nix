# Relic: State Manifest
#
# A list of the persistent state STC's enabled relics create: where it is,
# what it is, and what kind of data it holds. Each relic that creates state
# imports this module and appends to stc.relics.state.paths under its own
# enable, deriving every path from its options rather than repeating a default.
#
# Read it with:
#   nix eval --json .#nixosConfigurations.<host>.config.stc.relics.state.paths
#
# DESCRIPTIVE ONLY. Nothing in STC reads this list: it cannot break a build or
# a boot, and it backs nothing up. It is the input to a consumer's backup job or
# to stc.relics.impermanence.extraDirectories, not a replacement for either.
# Wiring it into impermanence is a separate, deliberate change (#64).
#
# Scope: state created by NixOS relics. Home Manager relics live in another
# module system and are not listed (zen-browser's profile, ~/.zen, is the one
# with real state there). A cogitator that enables an upstream service
# (docker-server enables Docker, whose /var/lib/docker holds the consumer's own
# images and volumes) does not declare that service's state here.
{lib, ...}: {
  options.stc.relics.state.paths = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        path = lib.mkOption {
          type = lib.types.strMatching "/.*";
          description = "Absolute path of the file or directory.";
        };
        type = lib.mkOption {
          type = lib.types.enum ["file" "directory"];
          description = ''
            Whether the path is a file or a directory — which list it belongs
            to in stc.relics.impermanence (extraFiles or extraDirectories), or
            how a backup tool should take it.
          '';
        };
        description = lib.mkOption {
          type = lib.types.str;
          description = "What the path holds, and what breaks without it.";
        };
        kind = lib.mkOption {
          type = lib.types.enum ["data" "credentials" "cache" "log"];
          description = ''
            The nature of the data, which is what a backup decision needs:

            - `data`: lost means lost; back it up.
            - `credentials`: keys and secrets; back them up, and encrypt them
              apart from ordinary data.
            - `cache`: rebuilt on its own; no need to back it up.
            - `log`: history, not state; keep it for as long as you need it.
          '';
        };
      };
    });
    default = [];
    description = ''
      Persistent state created by the enabled STC relics. Descriptive only:
      nothing reads it, and it guarantees no backup by itself.
    '';
  };
}
