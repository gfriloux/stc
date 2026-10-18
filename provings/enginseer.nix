# Proving: enginseer cogitator (Home Manager)
#
# The first proving in this suite to test a Home Manager cogitator, and the one
# that settles how the others will be tested. cogitator.home.enginseer has
# shipped since v0.1.0 with zero behavioural coverage.
#
# ---------------------------------------------------------------------------
# Why a nixosTest, and not a build of home.activationPackage
#
# #50 leaves the mechanism open and names the cheaper option: "HM
# build/activation check is acceptable". The answer here is no, deliberately.
#
# Building home.activationPackage proves the configuration *evaluates and
# builds*. That is exactly what `nix flake check` and the Purity Seals already
# prove, and the docs of this pillar put it in those words: where they prove a
# flake evaluates, the provings prove a system works. A proving that reduced to
# a `nix build` would add nothing to the existing gate while carrying the name of
# a proving — it would read as coverage.
#
# And enginseer's claims are runtime claims. An alias that resolves to `bat` in a
# shell that actually started; delta being the pager `git` itself selects; the
# session carrying the variable that hands Ctrl-R to atuin. None of that is
# visible in a drvPath.
#
# So the node imports Home Manager's NixOS module and attaches the cogitator to a
# test user. Activation then becomes an ordinary systemd unit of the node —
# measured, `home-manager-proving.service` — and `wait_for_unit` applies.
#
# ---------------------------------------------------------------------------
# Three bench concessions, in the same spirit as the external-image pattern's
# five. None is a recommendation for how to wire a consumer.
#
#   users.users.proving.shell = pkgs.fish
#       Home Manager does not set the login shell — measured. Without this there
#       is no fish to start, and the login-shell half of the profile could not be
#       observed. It is the node's job, not the cogitator's claim.
#
#   home-manager.useGlobalPkgs = true
#       HM uses the node's `pkgs` instead of importing its own nixpkgs. Keeps one
#       instance at evaluation, and keeps the suite's published note about unfree
#       scoping ("the instance has to be the one *building* the test") true for
#       Home Manager provings too. With a second instance imported by HM that
#       sentence would quietly become false.
#
#   home-manager.useUserPackages = true
#       Packages land in users.users.<u>.packages, hence under
#       /etc/profiles/per-user/<u>, which is a deterministic path. Measured: both
#       options change the closure, so neither is a no-op worth hiding.
#
#   programs.fish.enable = true
#       Forced by an upstream assertion, met while building this: a user whose
#       login shell is fish needs the system-level module too, or "the fish shell
#       [lacks] the basic nix directories in its PATH and might make logging in as
#       that user impossible". Since this proving does log in and run fish, the
#       assertion is satisfied rather than suppressed with
#       ignoreShellProgramCheck. It does not weaken what is asserted below: the
#       system module does not render ~/.config/fish/config.fish — Home Manager
#       does — and measured, it defines no `cat` alias of its own.
#
# Measured and worth saying: neither this profile nor cogitator-desktop needs the
# unfree pkgs instance. `gaming` remains the only unfree proving in the suite.
#
# ---------------------------------------------------------------------------
# Discrimination
#
# Every assertion below was measured against a reference node carrying Home
# Manager and the same test user but *no STC cogitator*. On that node, HM renders
# exactly five files — environment.d/10-home-manager.conf, three
# fontconfig/conf.d/* and systemd/user/tray.target — plus two .keep stubs, and
# programs.fish.enable and services.gpg-agent.enable are both false. So none of
# the paths read below exists without the cogitator.
#
# Three things that measurement changed, each of which would have produced an
# assertion that proved nothing:
#
#   - The rendered config.fish carries seven aliases, but four of them
#     (ls, ll, la, lt) come from Home Manager's own programs.lsd module. Only
#     cat → bat, cp → xcp and ping → prettyping come from this cogitator's
#     shellAliases, and only those three are asserted.
#   - delta is not wired through core.pager. Measured in the rendered git config:
#     the integration is [pager] diff/log/show/blame plus [delta] diffFilter. A
#     check on core.pager would have returned nothing at all.
#   - programs.fzf.historyWidget.command = "" does not change the body of
#     config.fish. Measured against the counterfactual, the only difference is a
#     store path: the setting travels through hm-session-vars.fish as
#     FZF_CTRL_R_COMMAND (empty here, "fzf" by default). The session variable is
#     what proves it; a grep of config.fish would not.
#
# Deliberately not asserted:
#
#   - that gpg-agent is *running*. The agent is a user unit and would need a
#     live user session; what the cogitator decides is which pinentry it carries,
#     and that is readable in the rendered unit. The running agent is upstream's.
#   - the mere presence of packages on PATH (bat, git, jq…). A list of packages
#     proves a list of packages was written.
#   - everything HM renders unasked (fontconfig, environment.d, tray.target):
#     green with or without STC.
# ---------------------------------------------------------------------------
{
  self,
  inputs,
}: {
  name = "enginseer";

  nodes.machine = {pkgs, ...}: {
    imports = [inputs.home-manager.nixosModules.home-manager];

    # See the header: bench concessions, not claims of the cogitator.
    users.users.proving = {
      isNormalUser = true;
      home = "/home/proving";
      shell = pkgs.fish;
    };

    # Required by an upstream assertion once a user's login shell is fish.
    programs.fish.enable = true;

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;

      users.proving = {
        imports = [self.homeModules.cogitator-enginseer];
        stc.cogitator.enginseer.enable = true;
        home.stateVersion = "25.11";
      };
    };
  };

  testScript = ''
    HOME = "/home/proving"
    FISH = f"{HOME}/.config/fish/config.fish"

    def as_user(cmd):
        """Run a command as the test user, through their login shell."""
        return machine.succeed(f"su - proving -c {cmd!r}")

    machine.wait_for_unit("multi-user.target")

    with subtest("the profile activates, and the host stays healthy"):
        # The unit name is measured, not guessed: attaching a cogitator through
        # home-manager.users.<u> produces exactly home-manager-<u>.service in the
        # node's systemd.services. One invalid option anywhere in the profile
        # turns this red.
        machine.wait_for_unit("home-manager-proving.service")
        state = machine.succeed("systemctl is-system-running --wait || true").strip()
        assert state == "running", f"unexpected system state: {state}"

    with subtest("the three aliases the cogitator declares are in the shell"):
        # Only three. The other four aliases in this file are programs.lsd's —
        # see the header. Asserting those would measure Home Manager.
        rendered = machine.succeed(f"cat {FISH}")
        for alias in ["alias cat bat", "alias cp xcp", "alias ping prettyping"]:
            assert alias in rendered, f"{alias!r} missing from the rendered config"

        # And they resolve in a shell that really started. Measured: the aliases
        # sit inside a `status is-interactive; and begin … end` block, so a
        # non-interactive `fish -c` would not define them — hence -i.
        resolved = as_user("fish -i -c 'type -t cat'").strip()
        assert resolved == "function", (
            f"`cat` resolves as {resolved!r}, not as the alias function fish "
            "builds from shellAliases"
        )

    with subtest("the oh-my-posh prompt is initialised from the shipped theme"):
        # Two halves, because either alone is weak: the init line names a path,
        # and the path has to hold the file the cogitator ships from its own
        # directory. Measured: this line is *outside* the interactive block, so
        # it applies to every shell.
        theme = f"{HOME}/.config/oh-my-posh/dracula.omp.json"
        rendered = machine.succeed(f"cat {FISH}")
        assert f"oh-my-posh init fish --config {theme}" in rendered, (
            "the prompt is not initialised from the declared theme path"
        )
        machine.succeed(f"test -s {theme}")

    with subtest("delta is the pager git itself selects"):
        # Behaviour, not a file: git is asked what it would use. Measured, the
        # integration is [pager] diff/log/show/blame — *not* core.pager, which is
        # empty, so the obvious check would have passed for the wrong reason.
        pager = as_user("git config --get pager.diff").strip()
        assert pager.endswith("/bin/delta"), (
            f"git's diff pager is {pager!r}, not delta"
        )
        # Measured in the rendered config, after getting the section wrong once
        # by reading a grep instead of the file: diffFilter lives under
        # [interactive], not under [delta]. The [delta] section carries only
        # `features`, which is the catppuccin wiring.
        difffilter = as_user("git config --get interactive.diffFilter").strip()
        assert "/bin/delta" in difffilter, (
            f"interactive.diffFilter is {difffilter!r} — enableGitIntegration did "
            "not apply"
        )

    with subtest("direnv is hooked into the shell and silenced"):
        # All three sub-options of the cogitator's direnv block, each where it is
        # observable: the hook in the shell, nix-direnv's library on disk, and
        # `silent` in direnv's own config.
        rendered = machine.succeed(f"cat {FISH}")
        assert "direnv hook fish | source" in rendered, "direnv is not hooked into fish"
        machine.succeed(f"test -s {HOME}/.config/direnv/lib/hm-nix-direnv.sh")
        # `silent = true` does not write the word "silent" anywhere — measured,
        # it renders a [global] section with log_filter = "^$" and
        # log_format = "-". Asserting the option name would have been red for the
        # wrong reason.
        toml = machine.succeed(f"cat {HOME}/.config/direnv/direnv.toml")
        assert 'log_filter = "^$"' in toml, f"direnv is not silenced:\n{toml}"

    with subtest("Ctrl-R belongs to atuin, not to fzf"):
        # The one assertion the cogitator's own comment asks for: atuin and fzf
        # both want Ctrl-R, and the profile clears fzf's widget to make atuin's
        # win explicit rather than incidental.
        #
        # Measured against the counterfactual: clearing it leaves the body of
        # config.fish untouched and travels through hm-session-vars.fish instead.
        # So the session variable is the only place this is visible — empty here,
        # "fzf" if the setting were left at its default.
        # Double quotes inside, single quotes outside. Two consecutive single
        # quotes anywhere in this script — even in a comment — would terminate
        # the Nix indented string that holds it.
        value = as_user('fish -c "set -q FZF_CTRL_R_COMMAND; and echo SET:$FZF_CTRL_R_COMMAND"').strip()
        assert value == "SET:", (
            f"FZF_CTRL_R_COMMAND is {value!r} — expected it set and empty, which "
            "is what hands Ctrl-R to atuin"
        )
        # And atuin's own init is in the shell, so there is something to hand it to.
        rendered = machine.succeed(f"cat {FISH}")
        assert "atuin-fish-config.fish" in rendered, "atuin is not initialised in fish"

    with subtest("ssh carries multiplexing only, without Home Manager's legacy block"):
        # The cogitator's comment claims two things: the universal multiplexing
        # settings are shipped, and enableDefaultConfig = false drops HM's legacy
        # default block. The second needs the counterfactual to be assertable at
        # all — measured, turning it back on adds AddKeysToAgent, Compression,
        # ForwardAgent, HashKnownHosts, ServerAliveCountMax, ServerAliveInterval
        # and UserKnownHostsFile. So the *absence* of those is the discriminating
        # half; the presence of ControlMaster does not tell the two cases apart.
        config = machine.succeed(f"cat {HOME}/.ssh/config")
        for line in [
            "ControlMaster auto",
            "ControlPath ~/.ssh/sockets/%r@%h:%p",
            "ControlPersist 60m",
        ]:
            assert line in config, f"{line!r} missing from:\n{config}"
        for leaked in ["ForwardAgent", "UserKnownHostsFile", "HashKnownHosts"]:
            assert leaked not in config, (
                f"{leaked} is present, so Home Manager's legacy default block was "
                f"not dropped:\n{config}"
            )
        # The multiplexing sockets need somewhere to live, and the profile says so.
        machine.succeed(f"test -d {HOME}/.ssh/sockets")

    with subtest("gpg-agent is configured headless-safe"):
        # pinentry-curses, from the cogitator's mkDefault. This is the lower half
        # of the cross-profile claim that provings/home-desktop.nix completes:
        # cogitator-desktop mkForces pinentry-qt over this value, and that
        # override is only observable on a user carrying both profiles.
        # Measured, after looking in the wrong file first: the choice lands in
        # ~/.gnupg/gpg-agent.conf as a `pinentry-program` line, and the rendered
        # systemd user unit says nothing about it at all. The unit only carries
        # GNUPGHOME and the gpg-agent ExecStart.
        conf = machine.succeed(f"cat {HOME}/.gnupg/gpg-agent.conf")
        assert "pinentry-curses" in conf, (
            f"the agent does not carry the headless pinentry:\n{conf}"
        )
        assert "pinentry-qt" not in conf, (
            "pinentry-qt is present on a node that does not import cogitator-desktop"
        )
        # The unit exists, which is what makes the *absence* of a gpg-agent unit
        # the assertable half of desktop's "inert if gpg-agent is not enabled".
        machine.succeed(f"test -s {HOME}/.config/systemd/user/gpg-agent.service")

    with subtest("the catppuccin flavour reaches a tool that renders with it"):
        # catppuccin.flavor = "frappe" with autoEnable, asserted where it lands
        # rather than by reading the option back: bat's config has to point at the
        # Frappe theme file the module installs.
        config = machine.succeed(f"cat {HOME}/.config/bat/config")
        assert "Catppuccin Frappe" in config, (
            f"bat is not themed with the declared flavour:\n{config}"
        )
  '';
}
