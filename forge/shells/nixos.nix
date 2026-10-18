# Forge Shell: nixos
#
# Development shell for managing NixOS system configurations.
# Covers formatting, linting, secrets, deployment inspection,
# generation diffing, and upstream version tracking for packages
# that are not in nixpkgs — the full NixOS operator toolkit.
#
# nvfetcher is a generator, never a build-time step: it writes
# _sources/generated.json, that file gets committed, and derivations
# read it with lib.importJSON. Version detection stays an explicit
# act, so evaluation stays pure. Renovate cannot replace it here —
# a custom regex manager updates the version but not the hash that
# must change with it, and the only mechanism that could recompute
# the hash (postUpgradeTasks) needs allowedCommands, a self-hosted
# option this repository has no access to (hosted Mend app).
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
    nvfetcher
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
    echo "  nvfetcher       bump out-of-nixpkgs sources (commit the JSON)"
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
