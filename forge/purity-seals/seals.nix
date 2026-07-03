# Purity Seals — CI check builders.
#
# A passing seal stamps a source tree as inspected and free of heresy: no dead
# Nix, no antipatterns, no leaked secrets, clean formatting. Each builder is a
# pure function from a source path to a check derivation.
#
# `pkgs-unfree` is a nixpkgs instance with allowUnfree — required only by the
# terraform seal (Terraform is BSL-licensed since v1.6). It is scoped here so
# the other seals never pull in unfree packages.
{
  pkgs,
  pkgs-unfree,
}: let
  # Generic seal: run one command in the source tree, succeed if it exits 0.
  mkCheck = name: code: path:
    pkgs.runCommand name {} ''
      cd ${path}
      echo Running check ${name}
      ${code}
      mkdir "$out"
    '';

  nix = path:
    pkgs.runCommand "check-nix" {} ''
      cd ${path}
      echo Running check nix
      ${pkgs.deadnix}/bin/deadnix --fail
      ${pkgs.statix}/bin/statix check
      ${pkgs.alejandra}/bin/alejandra --check .
      mkdir "$out"
    '';

  terraform = path:
    pkgs.runCommand "check-terraform" {} ''
      cd ${path}
      echo Running check terraform
      ${pkgs-unfree.terraform}/bin/terraform fmt -diff -write=false -check -recursive
      ${pkgs.tflint}/bin/tflint --recursive
      ${pkgs.findutils}/bin/find . -type d | ${pkgs.findutils}/bin/xargs -I {} -t ${pkgs.tfsec}/bin/tfsec --exclude-downloaded-modules {}
      mkdir "$out"
    '';

  ansible = path:
    pkgs.runCommand "check-ansible" {} ''
      cd ${path}
      echo Running check ansible
      set -euo pipefail
      export HOME="$TMPDIR"
      export ANSIBLE_LOCAL_TEMP="$TMPDIR/.ansible/tmp"
      export ANSIBLE_REMOTE_TEMP="$TMPDIR/.ansible/remote_tmp"
      mkdir -p "$ANSIBLE_LOCAL_TEMP" "$ANSIBLE_REMOTE_TEMP"
      ${pkgs.ansible-lint}/bin/ansible-lint --offline --profile production --exclude=tests .
      mkdir "$out"
    '';

  shell = path:
    pkgs.runCommand "check-shell" {} ''
      cd ${path}
      echo Running check shell
      ${pkgs.findutils}/bin/find . -name '*.sh' | ${pkgs.findutils}/bin/xargs -I {} -t ${pkgs.shellcheck}/bin/shellcheck {}
      ${pkgs.shfmt}/bin/shfmt -d -s -i 2 -ci .
      mkdir "$out"
    '';

  markdown = {
    path,
    args ? "",
  }:
    pkgs.runCommand "check-markdown" {} ''
      cd ${path}
      echo Running check markdown
      ${pkgs.rumdl}/bin/rumdl check ${args} --exclude ".venv" .
      mkdir "$out"
    '';
in {
  inherit nix terraform ansible shell markdown;
  gitleaks = mkCheck "check-gitleaks" "${pkgs.gitleaks}/bin/gitleaks dir --no-banner --verbose --redact";
}
