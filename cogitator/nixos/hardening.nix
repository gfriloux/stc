# Cogitator: Hardening Suite
# One option to harden them all.
#
# Activates kernel, network, filesystem, and SSH hardening in a single toggle.
# For surgical control, import the individual relics instead and enable them
# à la carte: stc.hardening.kernel.enable, stc.hardening.ssh.enable, etc.
{ config, lib, ... }:

let
  cfg = config.stc.hardening;
in
{
  imports = [
    ../../relics/nixos/hardening/kernel.nix
    ../../relics/nixos/hardening/network.nix
    ../../relics/nixos/hardening/filesystem.nix
    ../../relics/nixos/hardening/ssh.nix
  ];

  options.stc.hardening = {
    enable = lib.mkEnableOption "full hardening suite (kernel + network + filesystem + SSH)";
  };

  config = lib.mkIf cfg.enable {
    stc.hardening.kernel.enable = true;
    stc.hardening.network.enable = true;
    stc.hardening.filesystem.enable = true;
    stc.hardening.ssh.enable = true;
  };
}
