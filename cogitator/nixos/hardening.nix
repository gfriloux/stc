# Cogitator: Hardening Suite
# One option to harden them all.
#
# Activates kernel, network, filesystem, SSH, module-blacklist, scheduler, audit
# and firewall hardening in a single toggle. For surgical control, import the individual relics
# instead and enable them à la carte: stc.relics.hardening.kernel.enable,
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
    ../../relics/nixos/hardening/scheduler.nix
    ../../relics/nixos/hardening/audit.nix
    ../../relics/nixos/hardening/firewall.nix
    (lib.mkRenamedOptionModule ["stc" "hardening" "enable"] ["stc" "cogitator" "hardening" "enable"])
  ];

  options.stc.cogitator.hardening = {
    enable = lib.mkEnableOption "full hardening suite (kernel + network + filesystem + SSH + module blacklist + scheduler access + audit + firewall)";
  };

  config = lib.mkIf cfg.enable {
    # mkDefault on all eight, not bare true: the eight relics are independent and
    # this profile writes nothing that assumes any one of them, so a consumer is
    # entitled to take the suite and decline a part of it — their own sshd
    # configuration, their own cron policy. At normal priority that cost a
    # `mkForce`, because a plain `= false` collided
    # ("has conflicting definition values") with the line below. The header
    # already offered the other escape, importing the relics à la carte, which
    # means giving up this profile's single toggle to subtract one item from it.
    #
    # Measured, two of six: with the ssh relic and with the scheduler relic
    # forced off, the configuration evaluates and stays coherent — nothing else
    # here depends on them. That is what separates these six from the relic
    # enablements this audit deliberately left pinned (see the triage).
    stc.relics.hardening.kernel.enable = lib.mkDefault true;
    stc.relics.hardening.network.enable = lib.mkDefault true;
    stc.relics.hardening.filesystem.enable = lib.mkDefault true;
    stc.relics.hardening.ssh.enable = lib.mkDefault true;
    stc.relics.hardening.modules.enable = lib.mkDefault true;
    # Inert unless the host actually runs cron or atd — STC schedules with
    # systemd timers, so this only bites a consumer who enables one of them.
    stc.relics.hardening.scheduler.enable = lib.mkDefault true;
    # auditd with the baseline ruleset (#31). Adds audit=1 to the kernel command
    # line and writes /var/log/audit.
    stc.relics.hardening.audit.enable = lib.mkDefault true;
    # Asserts the NixOS firewall is on and logs refused connections (#33). A
    # host filtered by another layer declines it.
    stc.relics.hardening.firewall.enable = lib.mkDefault true;
  };
}
