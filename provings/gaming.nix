# Proving: gaming cogitator
# Boots the "gaming on an AMD GPU" profile: the AMD GPU relic (VDPAU/VAAPI plus
# 32-bit drivers) composed with the Pipewire relic and programs.steam.
#
# Scope note — nothing here launches Steam or a game. The VM has no GPU, no
# registry credentials and no outbound network. What STC owns is the wiring, and
# the wiring is what gets read from disk.
#
# Steam is unfree, so this proving is the one line of provings/default.nix built
# from a nixpkgs instance that allows it. The reasoning, and the two closed
# alternatives, are in that file.
#
# Who proves what, measured on four nodes (bare / programs.steam alone / the AMD
# relic alone / the whole cogitator), because the cogitator has three halves and
# they overlap more than they look:
#
#   - `programs.steam.enable` **alone** already sets hardware.graphics.enable32Bit
#     and hardware.steam-hardware.enable. So /run/opengl-driver-32 and the udev
#     rules prove the *cogitator*, not the AMD relic — the comments below say so
#     rather than letting a reader credit the relic for them.
#   - The AMD relic's own, non-overlapping claim is its driver packages:
#     hardware.graphics.extraPackages is empty on a bare node **and** on a
#     steam-only node, and carries libvdpau + libva-vdpau-driver with the relic.
#     That is the assertion that discriminates, and it is the one this file leans
#     on for the GPU half.
#   - The Pipewire relic's claims are rtkit (false upstream) and the 32-bit ALSA
#     bridge (false upstream, and false with programs.steam alone).
{self}: {
  name = "gaming";

  nodes = {
    machine = {
      imports = [self.nixosModules.cogitator-gaming];
      stc.cogitator.gaming.enable = true;
    };

    # The cogitator declares exactly one option of its own. Without this node it
    # would be untested, and the "closed by default" assertion on the first node
    # would have nothing to be the counterpart of.
    remoteplay = {
      imports = [self.nixosModules.cogitator-gaming];
      stc.cogitator.gaming = {
        enable = true;
        steam.remotePlay = true;
      };
    };
  };

  testScript = ''
    start_all()

    machine.wait_for_unit("multi-user.target")

    with subtest("steam is wired, with its hardware rules"):
        machine.succeed("test -e /run/current-system/sw/bin/steam")
        # programs.steam pulls in hardware.steam-hardware, which is what makes a
        # controller usable without root. Satisfied by the steam module alone —
        # the cogitator is what enables it, so this proves the profile, not the
        # AMD relic.
        machine.succeed("test -e /run/current-system/sw/bin/steam-run")

    with subtest("the AMD GPU relic contributes its drivers"):
        # The discriminating GPU assertion: measured, hardware.graphics
        # .extraPackages is empty both on a bare node and on a node with
        # programs.steam alone, and carries libva-vdpau-driver only with the
        # relic. This is the file that package puts in the merged driver tree.
        machine.succeed("test -e /run/opengl-driver/lib/dri/vdpau_drv_video.so")

    with subtest("32-bit graphics are available for Proton"):
        # Both halves of the cogitator ask for this (the relic for DXVK/Proton,
        # programs.steam for its own runtime), so it cannot attribute the
        # behaviour to the relic — it proves the composition boots with 32-bit
        # drivers in place, which is what a consumer actually depends on.
        machine.succeed("test -L /run/opengl-driver-32")
        machine.succeed("test -L /run/opengl-driver")

    with subtest("audio is wired for 32-bit games"):
        # rtkit is off upstream; the Pipewire relic turns it on.
        machine.succeed("systemctl cat rtkit-daemon.service")

        # alsa.support32Bit is false upstream *and* false with programs.steam
        # alone, so this line is the Pipewire relic's own. It is the bridge
        # 32-bit Wine and Steam's runtime need to reach Pipewire at all.
        alsa = machine.succeed("cat /etc/alsa/conf.d/49-pipewire-modules.conf")
        assert "libs.32Bit" in alsa, f"the 32-bit ALSA bridge is missing:\n{alsa}"

    with subtest("remote play is closed unless asked for"):
        # The counterpart of the remoteplay node below. Without this the opt-in
        # would look proven while a silent default could have opened the ports.
        rules = machine.succeed("iptables -S")
        assert "27031" not in rules, f"remote play ports are open by default:\n{rules}"

    with subtest("remote play opens exactly the ports Steam needs"):
        remoteplay.wait_for_unit("multi-user.target")
        rules = remoteplay.succeed("iptables -S")
        # Measured bounds: UDP 27031-27035, and no TCP range at all. Writing
        # 27036 here — the number Steam's own documentation mentions — would turn
        # this red for a reason that has nothing to do with STC.
        assert "27031:27035" in rules, f"the remote play range is not open:\n{rules}"
        assert "-p udp" in rules, f"the range is not UDP:\n{rules}"
  '';
}
