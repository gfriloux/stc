# Relic: AppArmor
# Turns AppArmor on, and makes Docker confine every container with its
# docker-default profile — which stock NixOS silently does not do.
#
# With security.apparmor.enable alone, `docker inspect` reports
# AppArmorProfile=docker-default and `docker info` lists apparmor, yet the
# container runs unconfined and no policy is loaded. Measured, three causes:
#   - containerd decides the host supports AppArmor only if
#     /sbin/apparmor_parser exists (vendored containerd
#     pkg/apparmor/apparmor_linux.go, hostSupports()), an FHS path NixOS does
#     not have. Docker then never loads docker-default, and says nothing.
#   - dockerd runs `apparmor_parser` from its PATH to load the profile.
#   - The generated profile includes <abstractions/base>, which NixOS provides
#     and which uses @{HOMEDIRS}; that variable comes from <tunables/global>,
#     included only if /etc/apparmor.d/tunables/global exists. NixOS does not
#     ship it, and with the first two fixed alone every `docker run` fails.
# And one more once it works: apparmor.service's reload unloads
# docker-default under the running containers (see the stub below). A
# restart of apparmor.service tears every profile down and still does; a
# container started or restarted afterwards is confined again.
#
# Docker only: rootless Docker and Podman are not covered.
# provings/apparmor.nix keeps a node with AppArmor and Docker but without this
# relic: the day its container is confined, upstream fixed it and the Docker
# half of this file can go.
#
# What it does not do: write host profiles. Distribution profiles assume FHS
# paths (/usr/bin/foo), not the Nix store, so they do not apply as they are;
# a hand-written sshd profile would have to allow the user shells sshd spawns,
# and the containerised services are confined by docker-default, not by a host
# profile. SELinux has no store labelling on NixOS and is out of scope.
#
# security.apparmor.enable adds `lsm=…,apparmor apparmor=1` to the kernel
# command line: it takes effect at the next boot, not at switch.
#
# ANSSI-BP-028 R37 (mandatory access control) and R45 (AppArmor profiles),
# both partial; CIS ~1.6.x. See docs reference/anssi-bp-028.md.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.stc.relics.hardening.apparmor;
in {
  options.stc.relics.hardening.apparmor = {
    enable = lib.mkEnableOption "AppArmor, with every Docker container confined by the docker-default profile";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      security.apparmor.enable = true;
    }

    (lib.mkIf config.virtualisation.docker.enable {
      # Recreated at every boot, so it survives an impermanent root.
      systemd.tmpfiles.rules = [
        "L+ /sbin/apparmor_parser - - - - ${pkgs.apparmor-parser}/bin/apparmor_parser"
      ];
      virtualisation.docker.extraPackages = [pkgs.apparmor-parser];

      # What it includes in turn (<tunables/home>, …) resolves through
      # apparmor-profiles, which nixpkgs already puts on the include path.
      security.apparmor.includes."tunables/global" = ''
        include "${pkgs.apparmor-profiles}/etc/apparmor.d/tunables/global"
      '';

      # A name for aa-remove-unknown, never loaded. apparmor.service's reload
      # (a switch that changes /etc/apparmor.d) runs aa-remove-unknown, which
      # unloads every kernel profile not named under /etc/apparmor.d — and the
      # kernel then moves the processes it confined to unconfined, for good.
      # dockerd loads docker-default at runtime, so every running container
      # lost it. NixOS only loads security.apparmor.policies, never this file;
      # were it loaded, an empty profile denies everything rather than nothing.
      security.apparmor.includes."docker-default" = ''
        profile docker-default {}
      '';
    })
  ]);
}
