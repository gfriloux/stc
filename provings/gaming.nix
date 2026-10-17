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
#   - `programs.steam.enable` **alone** already sets hardware.graphics.enable
#     and .enable32Bit, and hardware.steam-hardware.enable. So the 32-bit driver
#     tree is not the AMD relic's doing, whatever the relic's own comment
#     suggests.
#   - The AMD relic's own, non-overlapping claim is its driver packages:
#     hardware.graphics.extraPackages is empty on a bare node **and** on a
#     steam-only node, and carries libvdpau + libva-vdpau-driver with the relic.
#     That is the assertion that discriminates, and it is the one this file leans
#     on for the GPU half.
#   - The Pipewire relic's claims all discriminate here, unlike in the plasma
#     proving where nixpkgs' plasma6 module provides them: rtkit, the 32-bit ALSA
#     bridge and the PulseAudio compat socket are false on all three other nodes.
#
# What this proving does NOT assert, deliberately:
#
#   - `stc.relics.amdGpu.initrd` (early KMS). Measured, boot.initrd.kernelModules
#     is identical on all four nodes with the option off, so covering it needs a
#     third node whose only difference is a kernel module list — and a VM with no
#     AMD GPU cannot show the framebuffer that option exists for. The option is
#     opt-in and documented as such.
#   - `stc.relics.hardening.filesystem.gaming`, which the cogitator's own header
#     flags as the profile's one footgun ("Steam requires exec access to /tmp and
#     /dev/shm"). It is **not coverable in a nixosTest**: that flag only drops
#     `noexec` from `fileSystems."/tmp"` and `"/dev/shm"`, and the qemu-vm module
#     replaces the whole `fileSystems` set with `mkVMOverride`. See the
#     "filesystem mount hardening" scope limit on the provings documentation
#     page, which covers the same ground for the hardening proving.
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

    with subtest("steam is wired, with its controller rules"):
        machine.succeed("test -e /run/current-system/sw/bin/steam")

        # The udev half, which is what makes a controller usable without root.
        # Asserting steam-run next to steam would have been a duplicate: both come
        # from the same systemPackages list, so no configuration has one without
        # the other. These rules come from a separate package
        # (steam-devices-udev-rules) that programs.steam pulls in through
        # hardware.steam-hardware, measured false on a bare node.
        machine.succeed("test -e /etc/udev/rules.d/60-steam-input.rules")

    with subtest("the AMD GPU relic contributes its drivers"):
        # The discriminating GPU assertion: measured, hardware.graphics
        # .extraPackages is empty both on a bare node and on a node with
        # programs.steam alone, and carries libva-vdpau-driver only with the
        # relic. This is the file that package puts in the merged driver tree.
        machine.succeed("test -e /run/opengl-driver/lib/dri/vdpau_drv_video.so")

    with subtest("the 32-bit driver tree exists — upstream canary, not an STC claim"):
        # Honest about what this is: no STC change can turn it red. The subtest
        # above already proves programs.steam is on, and programs.steam alone
        # sets hardware.graphics.enable32Bit — so deleting enable32Bit from the
        # AMD relic, or the whole relic, leaves this green. It is kept as a
        # canary for an upstream change that would break Proton on every host
        # built from this profile, not as a regression detector for STC.
        machine.succeed("test -L /run/opengl-driver-32")
        machine.succeed("test -L /run/opengl-driver")

    with subtest("audio is wired for 32-bit games"):
        # rtkit is off on all three other nodes; the Pipewire relic turns it on.
        machine.succeed("systemctl cat rtkit-daemon.service")

        # alsa.support32Bit is false upstream *and* false with programs.steam
        # alone, so this line is the Pipewire relic's own. It is the bridge
        # 32-bit Wine and Steam's runtime need to reach Pipewire at all.
        alsa = machine.succeed("cat /etc/alsa/conf.d/49-pipewire-modules.conf")
        assert "libs.32Bit" in alsa, f"the 32-bit ALSA bridge is missing:\n{alsa}"

        # The third claim in the relic's header, "PulseAudio compat". It
        # discriminates here (false on the three other nodes), unlike in the
        # plasma proving where nixpkgs' plasma6 module switches Pipewire on by
        # itself — so it is asserted here and not there.
        machine.succeed("test -e /etc/systemd/user/pipewire-pulse.socket")

    # Both firewall subtests read `iptables -S`. That is the backend in use
    # (networking.nftables.enable is false on all four nodes), but it is a
    # rendering, not a claim: if STC or nixpkgs ever switches to nftables these
    # two go red for a framework reason. The ports below are the measured full
    # set, which is wider than Steam's documentation suggests:
    #   UDP range 27031-27035, UDP 10400/10401/27036, TCP 27036/27037.
    remote_play_ports = ["27031", "27036", "27037", "10400"]

    with subtest("remote play is closed unless asked for"):
        # The counterpart of the remoteplay node below. Without this the opt-in
        # would look proven while a silent default could have opened the ports.
        rules = machine.succeed("iptables -S")
        for port in remote_play_ports:
            assert port not in rules, f"port {port} is open by default:\n{rules}"

    with subtest("remote play opens the ports Steam needs, UDP and TCP"):
        remoteplay.wait_for_unit("multi-user.target")
        lines = remoteplay.succeed("iptables -S").splitlines()

        # Per line, not per blob: two independent substring tests over the whole
        # ruleset would pass with the range rendered on the wrong protocol, as
        # long as any udp rule existed anywhere.
        assert any(
            "27031:27035" in line and "-p udp" in line for line in lines
        ), f"the UDP remote play range is not open:\n{lines}"

        # 27037 is TCP-only in the upstream module, so it is what proves the TCP
        # half is opened at all — the half an earlier revision of this proving
        # wrongly claimed did not exist.
        assert any(
            "27037" in line and "-p tcp" in line for line in lines
        ), f"the TCP remote play ports are not open:\n{lines}"
  '';
}
