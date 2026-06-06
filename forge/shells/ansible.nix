# Forge Shell: Ansible
#
# Provides three ansible versions simultaneously:
#   ansible          — latest from nixpkgs unstable
#   ansible_2_16     — wrapped with correct PYTHONPATH (pinned from nixos-25.11)
#   ansible_2_17     — same
#
# The multi-version approach is intentional: real-world environments often run
# mixed ansible versions. Test against all of them without leaving the shell.
{
  pkgs,
  pkgs-stable,
  preCommitConfig,
}:

let
  wrapAnsible =
    name: pkg:
    pkgs-stable.runCommand name
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
          builtins.replaceStrings [ "ansible_" ] [ "" ] name
        } \
          --set PYTHONPATH "${pkg}/lib"
      '';
in
pkgs.mkShell {
  name = "stc-ansible";

  packages = [
    (wrapAnsible "ansible_2_16" pkgs-stable.ansible_2_16)
    (wrapAnsible "ansible_2_17" pkgs-stable.ansible_2_17)
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
