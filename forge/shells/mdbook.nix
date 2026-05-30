# Forge Shell: mdBook
#
# Rust-based documentation site generator.
# rumdl catches markdown lint issues before they become CI failures.
# just provides a standard task interface (serve, build, clean).
{ pkgs, preCommitConfig }:

pkgs.mkShell {
  name = "stc-mdbook";

  packages = with pkgs; [
    glow
    just
    mdbook
    pre-commit
    rumdl
  ];

  shellHook = ''
    echo "[stc:mdbook] Operational. The Archivum is ready to be written."
    echo "  mdbook  $(mdbook --version)"

    if [ ! -f .pre-commit-config.yaml ]; then
      cp ${preCommitConfig} .pre-commit-config.yaml
      chmod 644 .pre-commit-config.yaml
    fi

    if [ -d .git ] && [ ! -f .git/hooks/pre-commit ]; then
      pre-commit install -f --install-hooks
    fi

    if [ ! -f book.toml ] && [ ! -f justfile ]; then
      echo ""
      echo "  Tip: run 'mdbook init' to initialise a new book."
    fi
  '';
}
