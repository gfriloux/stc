# Forge Shell: vm
#
# Development shell for building and running NixOS VM images.
# qemu covers both image inspection (qemu-img) and booting the result.
# nix-tree + nvd help introspect closures and compare generations.
{ pkgs, preCommitConfig }:

pkgs.mkShell {
  name = "stc-vm";

  packages = with pkgs; [
    alejandra
    deadnix
    just
    nix-output-monitor
    nix-tree
    nvd
    qemu
    statix
  ];

  shellHook = ''
    echo "[stc:vm] Machine-spirits awakened. The Omnissiah watches over your images."
    echo ""
    echo "  just build    build the qcow2 image"
    echo "  just run      boot the image in QEMU/KVM"
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
