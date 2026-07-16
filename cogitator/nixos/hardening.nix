# Cogitator: Hardening Suite
# One option to harden them all.
#
# Activates kernel, network, filesystem, SSH, and module-blacklist hardening in a
# single toggle. For surgical control, import the individual relics instead and
# enable them à la carte: stc.relics.hardening.kernel.enable,
# stc.relics.hardening.ssh.enable, etc.
{
  config,
  lib,
  ...
}: let
  cfg = config.stc.cogitator.hardening;
in {
  imports = [
    ../../relics/nixos/hardening/kernel.nix
    ../../relics/nixos/hardening/network.nix
    ../../relics/nixos/hardening/filesystem.nix
    ../../relics/nixos/hardening/ssh.nix
    ../../relics/nixos/hardening/modules.nix
    (lib.mkRenamedOptionModule ["stc" "hardening" "enable"] ["stc" "cogitator" "hardening" "enable"])
  ];

  options.stc.cogitator.hardening = {
    enable = lib.mkEnableOption "full hardening suite (kernel + network + filesystem + SSH + module blacklist)";
  };

  config = lib.mkIf cfg.enable {
    stc.relics.hardening.kernel.enable = true;
    stc.relics.hardening.network.enable = true;
    stc.relics.hardening.filesystem.enable = true;
    stc.relics.hardening.ssh.enable = true;
    stc.relics.hardening.modules.enable = true;
  };
}
