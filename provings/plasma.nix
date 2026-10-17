# Proving: plasma cogitator
# Boots the Plasma 6 desktop profile on its own — no hardening socle, no YubiKey
# — which is the composition the cogitator actually claims: the Plasma 6 relic
# (SDDM + Wayland + XDG portal + desktop services) plus the Pipewire relic.
#
# What this adds over the workstation proving, which only checks that *a*
# display-manager unit exists: the relics' own claims. SDDM really is the display
# manager and really runs Wayland, the Plasma session is installed, the portal
# carries the wildcard the relic configures, and WirePlumber is pulled into the
# graphical session.
#
# Scope note — the graphical session is not brought up. Plasma is heavy in a VM;
# we wait for multi-user.target and read the rendered configuration and the unit
# files from disk, which is what STC owns. Same boundary as the workstation
# proving.
#
# Two claims are deliberately NOT asserted, because the assertion would be
# satisfied by the test framework rather than by STC. Measured on a *bare*
# nixosTest node: `services.pulseaudio.enable` is already false and
# `services.xserver.enable` is already false, so "PulseAudio is off" and "no X
# server" hold with none of these relics imported. An assertion that cannot
# distinguish the relic from the default proves nothing — see the review lesson
# recorded in the v0.14.0 ledger. `services.tumbler` is left out for a different
# reason: it ships no systemd unit at all (purely D-Bus activated), so there is
# nothing to read from disk.
{self}: {
  name = "plasma";

  nodes.machine = {
    imports = [self.nixosModules.cogitator-plasma];
    stc.cogitator.plasma.enable = true;
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    with subtest("SDDM is the display manager, and it runs Wayland"):
        unit = machine.succeed("systemctl cat display-manager.service")
        assert "sddm" in unit, f"display-manager is not SDDM:\n{unit}"

        conf = machine.succeed("cat /etc/sddm.conf.d/00-nixos.conf")
        # The relic's `wayland.enable` default. Flipping it to false renders
        # DisplayServer=x11 here, which is exactly the regression worth catching.
        assert "DisplayServer=wayland" in conf, f"not a Wayland greeter:\n{conf}"
        assert "DefaultSession=plasma.desktop" in conf, f"unexpected default session:\n{conf}"
        # The greeter's compositor, not just the session's: an X11 fallback would
        # leave DisplayServer alone and change this line.
        assert "kwin_wayland" in conf, f"the greeter is not compositing:\n{conf}"

    with subtest("the Plasma session is installed, not merely declared"):
        # Derive the directory from the configuration under test rather than
        # guessing it: the sessions do not live in the system profile but in a
        # synthetic "desktops" derivation that the display-manager module builds
        # from sessionPackages and that sddm.conf points at. Asserting a guessed
        # path is how this subtest failed the first time it ran.
        session_dirs = [
            line.split("=", 1)[1].strip()
            for line in machine.succeed("cat /etc/sddm.conf.d/00-nixos.conf").splitlines()
            if line.startswith("SessionDir=")
        ]
        assert len(session_dirs) == 1, f"expected one SessionDir, got {session_dirs}"
        machine.succeed(f"test -e {session_dirs[0]}/plasma.desktop")

    with subtest("XDG portal lets each application pick its backend"):
        portals = machine.succeed("cat /etc/xdg/xdg-desktop-portal/portals.conf")
        # The relic sets config.common.default = "*" explicitly; without that
        # line this file does not exist at all.
        assert "default=*" in portals, f"unexpected portal config:\n{portals}"
        machine.succeed("test -e /etc/systemd/user/xdg-desktop-portal.service")

    with subtest("audio is wired for a desktop session"):
        # rtkit grants Pipewire real-time priority on demand. Off by default
        # upstream, so this one is the relic's doing.
        machine.succeed("systemctl cat rtkit-daemon.service")
        machine.succeed("test -e /etc/systemd/user/pipewire.socket")
        machine.succeed("test -e /etc/systemd/user/wireplumber.service")

        # The single STC decision in the Plasma relic, and the reason this
        # subtest is not decorative: measured, the Pipewire relic alone leaves
        # wireplumber wantedBy ["pipewire.service"], and the Plasma relic adds
        # "default.target" so WirePlumber starts with the graphical session.
        # Drop that line from the relic and this symlink disappears.
        machine.succeed("test -e /etc/systemd/user/default.target.wants/wireplumber.service")

    with subtest("Dolphin's virtual filesystem is available"):
        # gvfs reaches the session through systemd.packages as a *user* unit,
        # not a system one.
        machine.succeed("test -e /etc/systemd/user/gvfs-daemon.service")
  '';
}
