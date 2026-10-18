# Proving: plasma cogitator
# Boots the Plasma 6 desktop profile on its own — no hardening socle, no YubiKey
# — which is the composition the cogitator actually claims: the Plasma 6 relic
# (SDDM + Wayland + XDG portal + desktop services) plus the Pipewire relic.
#
# What this adds over the workstation proving, which only checks that *a*
# display-manager unit exists: the relics' own claims. SDDM really is the display
# manager and really runs Wayland, the Plasma session is installed where the
# display manager will look for it, both of the relic's tunables reach the
# rendered configuration, the portal carries the wildcard the relic configures,
# WirePlumber is pulled into the graphical session, and the 32-bit ALSA bridge
# Steam and Wine depend on is actually wired.
#
# Scope note — the graphical session is not brought up. Plasma is heavy in a VM;
# we wait for multi-user.target and read the rendered configuration and the unit
# files from disk, which is what STC owns. Same boundary as the workstation
# proving.
#
# Every assertion below was measured on a *bare* nixosTest node and on a node
# carrying the plasma6 nixpkgs module without STC, so that each one can tell the
# relic apart from a default. That sweep removed four candidates: PulseAudio
# being off and the X server being off are nixpkgs defaults (true with none of
# these relics imported); and `services.pipewire.enable` / `xdg.portal.enable`
# are set by nixpkgs' own plasma6 module, so the Pipewire and portal *user
# units* exist even with STC's Pipewire relic removed from the cogitator. An
# assertion that cannot distinguish the relic from the default proves nothing,
# and reads as coverage — which is worse than an admitted gap.
{self}: {
  name = "plasma";

  nodes.machine = {
    imports = [self.nixosModules.cogitator-plasma];
    stc.cogitator.plasma.enable = true;

    # The relic's two tunables, both moved off their defaults so the subtest
    # below proves they are read rather than merely declared. The theme name is
    # deliberately one no package provides: the relic documents that it installs
    # no theme package, so what is under test is the plumbing, not the theme.
    stc.relics.plasma6.keyboardLayout = "fr";
    stc.relics.plasma6.sddmTheme = "stc-proving-theme";
  };

  # Second node: the same profile with its Pipewire relic declined by a *plain*
  # definition. The plainness is the whole point — before #86 this node could not
  # be built at all, because the cogitator pinned the value at normal priority
  # and `= false` raised "has conflicting definition values". A mkForce here
  # would prove nothing, since mkForce already worked.
  #
  # The assertion has to discriminate, which rules out the obvious candidates:
  # nixpkgs' own plasma6 module enables Pipewire, so its units survive the relic
  # being gone (already recorded at the top of this file). rtkit is the witness —
  # off by default upstream, enabled only by STC's Pipewire relic — and the
  # 32-bit ALSA bridge is the second.
  nodes.noaudio = {
    imports = [self.nixosModules.cogitator-plasma];
    stc.cogitator.plasma.enable = true;
    stc.relics.pipewire.enable = false;
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    sddm_conf = machine.succeed("cat /etc/sddm.conf.d/00-nixos.conf")

    with subtest("SDDM is the display manager, and it runs Wayland"):
        unit = machine.succeed("systemctl cat display-manager.service")
        assert "sddm" in unit, f"display-manager is not SDDM:\n{unit}"

        # Measured: taking the relic's documented X11 route instead
        # (wayland = false plus services.xserver.enable = true) renders
        # DisplayServer=x11 here, so this line does discriminate. That route only
        # became reachable once the relic stopped pinning services.xserver.enable
        # at normal priority — see the fix in relics/nixos/plasma6.nix.
        assert "DisplayServer=wayland" in sddm_conf, f"not a Wayland greeter:\n{sddm_conf}"
        assert "DefaultSession=plasma.desktop" in sddm_conf, f"unexpected default session:\n{sddm_conf}"

    with subtest("the Plasma session is installed, not merely declared"):
        # Derive the directory from the configuration under test rather than
        # guessing it: the sessions do not live in the system profile but in a
        # synthetic "desktops" derivation that the display-manager module builds
        # from sessionPackages and that sddm.conf points at. Asserting a guessed
        # path is how this subtest failed the first time it ran.
        session_dirs = [
            line.split("=", 1)[1].strip()
            for line in sddm_conf.splitlines()
            if line.startswith("SessionDir=")
        ]
        assert len(session_dirs) == 1, f"expected one SessionDir, got {session_dirs}"
        machine.succeed(f"test -e {session_dirs[0]}/plasma.desktop")

    with subtest("both relic tunables reach the rendered configuration"):
        assert "Current=stc-proving-theme" in sddm_conf, f"sddmTheme did not land:\n{sddm_conf}"

        # The relic's comment claims xkb.layout is still read without an X
        # server; this is the file that carries it, and it exists either way.
        keyboard = machine.succeed("cat /etc/X11/xorg.conf.d/00-keyboard.conf")
        assert '"XkbLayout" "fr"' in keyboard, f"keyboardLayout did not land:\n{keyboard}"

    with subtest("XDG portal lets each application pick its backend"):
        # The relic sets config.common.default = "*" explicitly; measured,
        # without that line this file does not exist at all — unlike the portal
        # service unit, which nixpkgs' plasma6 module brings in on its own.
        portals = machine.succeed("cat /etc/xdg/xdg-desktop-portal/portals.conf")
        assert "default=*" in portals, f"unexpected portal config:\n{portals}"

    with subtest("audio is wired for a desktop session"):
        # rtkit grants Pipewire real-time priority on demand. Off by default
        # upstream, so this one is the relic's doing.
        machine.succeed("systemctl cat rtkit-daemon.service")

        # The Pipewire relic's headline claim, and the only one that
        # discriminates: nixpkgs' plasma6 module enables Pipewire by itself, so
        # the pipewire user units prove nothing about STC. alsa.support32Bit is
        # false upstream, and measured, with STC's Pipewire relic removed this
        # file still exists but carries no libs.32Bit line. That bridge is what
        # Steam and 32-bit Wine need.
        alsa = machine.succeed("cat /etc/alsa/conf.d/49-pipewire-modules.conf")
        assert "libs.32Bit" in alsa, f"the 32-bit ALSA bridge is missing:\n{alsa}"

        # The single STC decision in the Plasma relic, and the reason this
        # subtest is not decorative: measured, the Pipewire relic alone leaves
        # wireplumber wantedBy ["pipewire.service"], and the Plasma relic adds
        # "default.target" so WirePlumber starts with the graphical session.
        # Drop that line from the relic and this symlink disappears.
        machine.succeed("test -e /etc/systemd/user/default.target.wants/wireplumber.service")

    with subtest("Dolphin's desktop services are available"):
        # gvfs reaches the session through systemd.packages as a *user* unit,
        # not a system one.
        machine.succeed("test -e /etc/systemd/user/gvfs-daemon.service")

        # Tumbler ships no unit NixOS activates — it is D-Bus activated — so the
        # service file in the system profile is what proves the relic turned it
        # on. Measured absent on a bare node.
        machine.succeed(
            "test -e /run/current-system/sw/share/dbus-1/services"
            "/org.xfce.Tumbler.Thumbnailer1.service"
        )

    with subtest("the Pipewire relic can be declined without mkForce"):
        noaudio.wait_for_unit("multi-user.target")

        # That this node booted at all is half the proof: the plain
        # `stc.relics.pipewire.enable = false` it carries would have failed to
        # evaluate before the cogitator stopped pinning the value.
        #
        # The other half is that declining it actually removes the relic rather
        # than only its option. Both witnesses are present on `machine` above
        # and must be gone here.
        noaudio.fail("systemctl cat rtkit-daemon.service")

        # Tolerant of the file's absence on purpose. The claim under test is
        # "no 32-bit bridge", which holds whether or not the file exists — and
        # whether it exists depends on services.pipewire.alsa.enable, which STC
        # does not own here (measured true today on a plasma6 node with the
        # relic declined, from upstream, while support32Bit is false). A bare
        # `succeed("cat ...")` would couple this proving to that upstream
        # default and fail one day with "No such file or directory" instead of a
        # meaningful message.
        alsa = noaudio.succeed(
            "cat /etc/alsa/conf.d/49-pipewire-modules.conf 2>/dev/null || true"
        )
        assert "libs.32Bit" not in alsa, (
            "the 32-bit ALSA bridge is still configured with the relic declined:\n"
            f"{alsa}"
        )

        # And Plasma itself is untouched: the point of the demotion is a Plasma
        # host without STC's audio stack, not a broken desktop.
        sddm = noaudio.succeed("cat /etc/sddm.conf.d/00-nixos.conf")
        assert "DefaultSession=plasma.desktop" in sddm, (
            f"declining the audio relic disturbed the session:\n{sddm}"
        )
  '';
}
