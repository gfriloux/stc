# Forge Shell: nixos
#
# Development shell for managing NixOS system configurations.
# Covers formatting, linting, secrets, deployment inspection,
# and generation diffing — the full NixOS operator toolkit.
{
  pkgs,
  preCommitConfig,
}:
pkgs.mkShell {
  name = "stc-nixos";

  packages = with pkgs; [
    alejandra
    deadnix
    just
    nh
    nix-output-monitor
    nix-tree
    nvd
    pre-commit
    serie
    sops
    statix
    tokei
    trivy
  ];

  shellHook = ''
    echo "[stc:nixos] The machine-spirits are catalogued. The Omnissiah approves."
    echo ""
    echo "  alejandra       format .nix files"
    echo "  statix check    lint for antipatterns"
    echo "  deadnix         find unused bindings"
    echo "  nvd diff        compare NixOS generations"
    echo "  nix-tree        inspect closure sizes"
    echo "  nh os switch    apply current config"
    echo ""

    if [ ! -f .pre-commit-config.yaml ]; then
      cp ${preCommitConfig} .pre-commit-config.yaml
      chmod 644 .pre-commit-config.yaml
    fi

    if [ -d .git ] && [ ! -f .git/hooks/pre-commit ]; then
      pre-commit install -f --install-hooks
    fi
  '';
}
