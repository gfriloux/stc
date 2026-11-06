# Forge Shell: Ansible
#
# Provides three ansible versions simultaneously:
#   ansible          — latest from nixpkgs unstable
#   ansible_2_16     — wrapped with correct PYTHONPATH (pinned from nixos-25.11)
#   ansible_2_17     — same
#
# The multi-version approach is intentional: real-world environments often run
# mixed ansible versions. Test against all of them without leaving the shell.
#
# The two pinned versions are legacy debt, kept on purpose. ansible-core 2.16 is
# the last release that manages Python 2.7/3.6 targets (CentOS 7), 2.17 the last
# for Python 3.7 (Amazon Linux 2). Both are end-of-life upstream and no longer
# in any maintained nixpkgs branch, so they come from the frozen nixos-25.11
# input, which receives no security fixes. Rebuilding them on unstable was
# tried and rejected: building ansible-core 2.16 against unstable's Python 3.12
# ran for over eleven minutes without finishing, for versions that would be
# just as unmaintained. Drop them when the last such host is gone.
{
  pkgs,
  pkgs-ansible-legacy,
  preCommitConfig,
}: let
  wrapAnsible = name: pkg:
    pkgs.runCommand name
    {
      buildInputs = [
        pkg
        pkgs.makeWrapper
      ];
    }
    ''
      mkdir -p $out/bin
      makeWrapper ${pkg}/bin/ansible $out/bin/${name} \
        --set PYTHONPATH "${pkg}/lib"
      makeWrapper ${pkg}/bin/ansible-playbook $out/bin/ansible-playbook_${
        builtins.replaceStrings ["ansible_"] [""] name
      } \
        --set PYTHONPATH "${pkg}/lib"
    '';
in
  pkgs.mkShell {
    name = "stc-ansible";

    packages = [
      (wrapAnsible "ansible_2_16" pkgs-ansible-legacy.ansible_2_16)
      (wrapAnsible "ansible_2_17" pkgs-ansible-legacy.ansible_2_17)
      pkgs.ansible
      pkgs.ansible-lint
      pkgs.fzf-make
      pkgs.gum
      pkgs.just
      pkgs.openssh_gssapi
      pkgs.pinentry-curses
      pkgs.pre-commit
      pkgs.rbw
      pkgs.shellcheck
      pkgs.shfmt
      pkgs.ansible-recap
      pkgs.molecule
      pkgs.python3Packages.molecule-plugins
      pkgs.python3Packages.docker
    ];

    shellHook = ''
      echo "[stc:ansible] Operational. Three ansible versions at your service."
      echo "  ansible         $(ansible --version | head -1)"
      echo "  ansible_2_16    $(ansible_2_16 --version | head -1)"
      echo "  ansible_2_17    $(ansible_2_17 --version | head -1)"

      if [ ! -f .pre-commit-config.yaml ]; then
        cp ${preCommitConfig} .pre-commit-config.yaml
        chmod 644 .pre-commit-config.yaml
      fi

      if [ -d .git ] && [ ! -f .git/hooks/pre-commit ]; then
        pre-commit install -f --install-hooks
      fi
    '';
  }
