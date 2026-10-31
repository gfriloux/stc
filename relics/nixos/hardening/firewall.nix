# Relic: Firewall
# Makes the NixOS firewall's default-deny inbound policy a checked claim, and
# logs the connections it refuses.
#
# The firewall is on by default in NixOS, so on most hosts this relic changes
# one thing: networking.firewall.logRefusedConnections, false upstream. With it,
# every refused TCP SYN lands in the kernel log as "refused connection: ...",
# on the iptables and the nftables backend alike (firewalld, if enabled,
# translates it into its own LogDenied instead). Refused UDP is not logged;
# logRefusedPackets would, for every packet, and upstream calls it a debugging
# aid.
#
# The relic owns no port list. Relics and consumers keep adding their ports to
# networking.firewall.allowedTCPPorts / allowedUDPPorts, or through upstream
# openFirewall options; nothing here ever opens or flushes the firewall.
#
# What it does not cover: ports published by Docker, whose DNAT rules sit ahead
# of networking.firewall (see relics/nixos/docker/guards.nix), and rate
# limiting, left to sshd's PerSourcePenalties (hardening/ssh.nix) rather than
# written twice, once per backend.
#
# No ANSSI-BP-028 rule covers the host firewall; the item comes from CIS
# ~3.5.x, informative only. See docs reference/anssi-bp-028.md.
{
  config,
  lib,
  ...
}: let
  cfg = config.stc.relics.hardening.firewall;
in {
  options.stc.relics.hardening.firewall = {
    enable = lib.mkEnableOption "the NixOS firewall as a checked default-deny baseline, with refused connections logged";

    logRefusedConnections = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Log every refused incoming TCP connection to the kernel log
        ("refused connection: ..."). Set false on a host whose network is
        noisy enough to drown the journal; the default-deny check stays.

        Set this option rather than networking.firewall.logRefusedConnections:
        the relic writes that one at normal priority, because nixpkgs'
        installation-device profile already holds a mkDefault false on it, and
        a second mkDefault would conflict.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.networking.firewall.enable;
        message = ''
          stc.relics.hardening.firewall: networking.firewall.enable is false, so
          this host has no default-deny inbound policy for the relic to vouch for.
          If another layer filters the traffic (your own nftables ruleset, a cloud
          security group), set stc.relics.hardening.firewall.enable = false to say
          so explicitly.
        '';
      }
      {
        # ferm and shorewall stop the NixOS firewall unit while leaving
        # networking.firewall.enable true, and ferm's default ruleset is empty.
        assertion = !(config.services.ferm.enable || config.services.shorewall.enable || config.services.shorewall6.enable);
        message = ''
          stc.relics.hardening.firewall: ferm or shorewall replaces the NixOS
          firewall here (its unit is disabled), so the relic cannot vouch for a
          default-deny policy it does not see. If your ruleset provides one, set
          stc.relics.hardening.firewall.enable = false to say so explicitly.
        '';
      }
    ];

    networking.firewall.logRefusedConnections = cfg.logRefusedConnections;
  };
}
