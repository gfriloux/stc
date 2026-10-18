# Proving: desktop cogitator (Home Manager)
#
# The second Home Manager proving, and the last cogitator in the repository
# without one. The mechanism is the one provings/enginseer.nix settled — see its
# header, and the "Proving a Home Manager cogitator" section of the docs, for why
# a nixosTest rather than a build of home.activationPackage, and for the bench
# concessions that are repeated here.
#
# ---------------------------------------------------------------------------
# Two nodes, and what each one is for
#
# `desktop` carries the profile alone and asserts its three relics in isolation.
# Isolation is the point: a proving named home-desktop that went red because
# something in enginseer broke would be a bad diagnosis.
#
# `composed` carries desktop *and* enginseer on the same user, for the one claim
# that cannot be observed any other way. cogitator/home/desktop.nix says:
#
#     # Graphical pinentry for gpg-agent. Overrides the headless-safe default set
#     # by cogitator-enginseer; inert if gpg-agent is not enabled.
#     services.gpg-agent.pinentry.package = lib.mkForce pkgs.pinentry-qt;
#
# The first half of that comment is a claim about a priority contest between two
# cogitators. Measured: pinentry-curses on enginseer alone (asserted in
# provings/enginseer.nix), pinentry-qt once desktop joins. That is the only
# cross-cogitator interaction proven anywhere in this suite.
#
# ---------------------------------------------------------------------------
# The second half of that comment — "inert if gpg-agent is not enabled" — is
# deliberately NOT asserted in a VM, and the reason is worth keeping.
#
# The plan called for asserting that no gpg-agent user unit exists on the
# desktop-alone node. Measured against the reference node (Home Manager and the
# same user, no STC cogitator at all): it has no gpg-agent unit either, because
# services.gpg-agent.enable is false without any cogitator. The assertion would
# be green whatever STC did.
#
# Inertness is an *evaluation* property, not a runtime one: desktop alone sets
# pinentry.package to pinentry-qt while gpg-agent.enable stays false, so nothing
# consumes the value and no gpg-agent.conf is rendered. Reading that from inside
# the VM would mean interpolating the option out of the same evaluation that
# built the node — a tautology. So it is measured by `nix eval` and written in
# the docs instead, the same treatment as docker-server's negative case and as
# boot.zfs.devNodes in provings/sarcophagus-aws.nix.
#
# ---------------------------------------------------------------------------
# Discrimination
#
# Reference node as above. It renders five files plus two .keep stubs, and
# `users.users.<u>.packages` holds a single `home-manager-path` — Home Manager
# aggregates everything into one derivation, which is why the zen-browser
# assertion below targets a *binary* and not a package name.
#
# What the profile adds on top of that reference, hence what discriminates:
# kitty/kitty.conf, the ghostty user unit with its overrides.conf,
# .local/share/dbus-1/services, and the contents of the profile.
#
# Two things measurement corrected before anything was written:
#
#   - zen-browser's binary is `zen-beta`, not `zen`: the cogitator imports
#     inputs.zen-browser.homeModules.beta. Asserting `zen` would have been red.
#   - The nerd fonts are *not* reachable at the obvious path. They matter,
#     because `stc.relics.gui.kitty.fonts.enable` (default true) is the only
#     option of STC's own across these three relics *beyond their three enable
#     toggles* — the relics declare four options in all, and the cogitator sets
#     the three toggles itself, so without this one it would have no tunable of
#     its own to prove. Enabling it installs seven font packages,
#     which is closure weight a consumer should know about. But measured,
#     environment.pathsToLink carries no /share/fonts entry, so
#     /etc/profiles/per-user/<u>/share/fonts is never populated: the fonts sit
#     inside the home-manager-path derivation, which
#     ~/.config/fontconfig/conf.d/10-hm-fonts.conf points at. Hence the
#     behavioural assertion through fc-list rather than a path test.
# ---------------------------------------------------------------------------
{
  self,
  inputs,
}: let
  # The two Home Manager-level concessions settled by provings/enginseer.nix,
  # bound once so this file's two nodes cannot disagree about them.
  #
  # It does no more than that, and the difference matters: the `composed` node
  # also has to match the *enginseer* node option for option — same user, same
  # home, same fish login shell, same stateVersion — or comparing its pinentry
  # against the pinentry-curses measured over there would prove nothing. That
  # alignment lives across two files and is maintained by hand; this `let` does
  # not enforce it. The fish concessions are deliberately outside it, since the
  # desktop-alone node does not take them.
  homeManagerBench = {
    useGlobalPkgs = true;
    useUserPackages = true;
  };
in {
  name = "home-desktop";

  nodes = {
    # The profile on its own.
    #
    # No fish here, unlike the enginseer node: this profile claims no shell, and
    # setting one would drag in the upstream assertion that a fish login shell
    # needs programs.fish.enable, for nothing.
    desktop = {...}: {
      imports = [inputs.home-manager.nixosModules.home-manager];

      users.users.proving = {
        isNormalUser = true;
        home = "/home/proving";
      };

      home-manager =
        homeManagerBench
        // {
          users.proving = {
            imports = [self.homeModules.cogitator-desktop];
            stc.cogitator.desktop.enable = true;
            home.stateVersion = "25.11";
          };
        };
    };

    # Both profiles, plus a consumer naming their own pinentry with a plain
    # definition. Added with issue #86: desktop used to write pinentry-qt with
    # mkForce, which beat not only enginseer's mkDefault (intended) but the
    # consumer too (not intended) — measured, someone asking for pinentry-gnome3
    # silently got pinentry-qt, no warning, no conflict. It is now
    # mkOverride 900, and this node is what keeps it there: with mkForce back,
    # the assertion below fails.
    consumer = {pkgs, ...}: {
      imports = [inputs.home-manager.nixosModules.home-manager];

      users.users.proving = {
        isNormalUser = true;
        home = "/home/proving";
        shell = pkgs.fish;
      };

      programs.fish.enable = true;

      home-manager =
        homeManagerBench
        // {
          users.proving = {
            imports = [
              self.homeModules.cogitator-enginseer
              self.homeModules.cogitator-desktop
            ];
            stc.cogitator = {
              enginseer.enable = true;
              desktop.enable = true;
            };
            # A plain definition, which is the whole point: it must win without
            # the consumer knowing anything about Nix priorities.
            services.gpg-agent.pinentry.package = pkgs.pinentry-gnome3;
            home.stateVersion = "25.11";
          };
        };
    };

    # Both profiles on one user — the only place a cross-cogitator claim is
    # proven in this suite. Mirrors the enginseer node exactly, fish included,
    # so that the pinentry comparison against it is sound.
    composed = {pkgs, ...}: {
      imports = [inputs.home-manager.nixosModules.home-manager];

      users.users.proving = {
        isNormalUser = true;
        home = "/home/proving";
        shell = pkgs.fish;
      };

      programs.fish.enable = true;

      home-manager =
        homeManagerBench
        // {
          users.proving = {
            imports = [
              self.homeModules.cogitator-enginseer
              self.homeModules.cogitator-desktop
            ];
            stc.cogitator = {
              enginseer.enable = true;
              desktop.enable = true;
            };
            home.stateVersion = "25.11";
          };
        };
    };
  };

  testScript = ''
    HOME = "/home/proving"
    PROFILE = "/etc/profiles/per-user/proving"

    start_all()
    desktop.wait_for_unit("multi-user.target")
    composed.wait_for_unit("multi-user.target")

    with subtest("both profiles activate, and both hosts stay healthy"):
        for machine in [desktop, composed]:
            machine.wait_for_unit("home-manager-proving.service")
            state = machine.succeed("systemctl is-system-running --wait || true").strip()
            assert state == "running", f"{machine.name}: unexpected state {state}"

    with subtest("the kitty relic renders its configuration"):
        # The reference node has no kitty.conf at all, so existence discriminates
        # here. Content is not asserted beyond that: the relic sets only
        # programs.kitty.enable, so everything inside the file is upstream's and
        # asserting it would measure Home Manager.
        desktop.succeed(f"test -s {HOME}/.config/kitty/kitty.conf")
        desktop.succeed(f"test -x {PROFILE}/bin/kitty")

    with subtest("the kitty relic's own option makes the nerd fonts visible"):
        # stc.relics.gui.kitty.fonts.enable, default true — the only option of
        # STC's own across these three relics beyond their three enable toggles
        # (four options in all, three of them set by the cogitator itself), and
        # the only one whose absence would be invisible without this check.
        # Seven font packages ride on it.
        #
        # Asserted through fontconfig rather than by a path test, after measuring
        # that the obvious path does not exist: environment.pathsToLink has no
        # /share/fonts entry, so /etc/profiles/per-user/<u>/share/fonts is never
        # populated. The fonts live inside the home-manager-path derivation, and
        # ~/.config/fontconfig/conf.d/10-hm-fonts.conf is what points at it. So
        # the behavioural question — can the session actually find these fonts —
        # is both the right one and the only one with a true answer.
        families = desktop.succeed("su - proving -c 'fc-list : family'")
        for family in ["JetBrainsMono Nerd Font", "Iosevka Nerd Font"]:
            assert family in families, (
                f"{family!r} is not visible to fontconfig — the relic's fonts "
                "option did not reach the session"
            )

    with subtest("the ghostty relic renders its user unit and overrides"):
        # Measured: both of these appear on the desktop node and on neither the
        # reference node nor the kitty-only path, so the pair is what tells the
        # ghostty relic apart from the kitty one.
        unit = f"{HOME}/.config/systemd/user/app-com.mitchellh.ghostty.service"
        desktop.succeed(f"test -s {unit}")
        desktop.succeed(f"test -s {unit}.d/overrides.conf")
        desktop.succeed(f"test -x {PROFILE}/bin/ghostty")

    with subtest("the zen-browser relic reaches the user's profile"):
        # The one relic of the three that renders no file at all, so the profile
        # is the only place it is observable — which is what useUserPackages buys
        # this proving.
        #
        # `zen-beta`, not `zen`: the cogitator imports
        # inputs.zen-browser.homeModules.beta. Measured by listing the built
        # profile; the obvious name would have been red.
        desktop.succeed(f"test -x {PROFILE}/bin/zen-beta")

    with subtest("the cogitator's own package list is installed"):
        # home.packages of cogitator/home/desktop.nix, as opposed to anything a
        # relic pulls in. libnotify ships no binary of that name, so the two that
        # do are checked.
        for binary in ["gimp", "vlc"]:
            desktop.succeed(f"test -x {PROFILE}/bin/{binary}")

    with subtest("on both profiles together, the graphical pinentry wins"):
        # The headline claim, and the only cross-cogitator interaction proven in
        # this suite.
        #
        # enginseer sets pinentry-curses with mkDefault and desktop forces
        # pinentry-qt over it. provings/enginseer.nix asserts the curses side on a
        # node carrying enginseer alone; this asserts the qt side on a node
        # carrying both. Neither node alone would show the contest.
        #
        # Read from ~/.gnupg/gpg-agent.conf, not from the systemd unit: measured
        # while writing the enginseer proving, the rendered unit says nothing
        # about the pinentry.
        conf = composed.succeed(f"cat {HOME}/.gnupg/gpg-agent.conf")
        assert "pinentry-qt" in conf, (
            f"the graphical pinentry did not win the contest:\n{conf}"
        )
        assert "pinentry-curses" not in conf, (
            f"the headless pinentry survived desktop's override:\n{conf}"
        )

    with subtest("but a consumer naming their own pinentry wins over the profile"):
        # The other half of the contest, and the one issue #86 added. desktop
        # has to beat enginseer's default without beating the person composing
        # them: mkOverride 900 sits between a default (1000) and a definition
        # (100). With mkForce (50) here instead, this node got pinentry-qt and
        # never knew its own definition had been discarded.
        conf = consumer.succeed(f"cat {HOME}/.gnupg/gpg-agent.conf")
        assert "pinentry-gnome3" in conf, (
            f"the consumer's own pinentry was discarded by the profile:\n{conf}"
        )
        assert "pinentry-qt" not in conf, (
            f"the profile's pinentry survived a plain consumer definition:\n{conf}"
        )

    with subtest("composing the two profiles breaks neither one"):
        # Cheap, and it is the regression this node is uniquely placed to catch:
        # a future relic added to either cogitator could collide with the other.
        # One claim from each profile, on the node that carries both.
        composed.succeed(f"test -s {HOME}/.config/kitty/kitty.conf")
        rendered = composed.succeed(f"cat {HOME}/.config/fish/config.fish")
        assert "alias cat bat" in rendered, (
            "enginseer's aliases did not survive composition with desktop"
        )
  '';
}
