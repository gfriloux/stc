# Forge Shell: zensical
#
# Python-based documentation site generator (successor to mkdocs).
# zensical and its plugin ecosystem are installed via pipenv to allow
# per-project plugin flexibility.
# rumdl handles markdown linting at the Nix level.
#
# On shell entry, `pipenv install` pulls the project's Pipfile.
# First run requires network access. Subsequent runs use the lockfile.
{
  pkgs,
  preCommitConfig,
}:
pkgs.mkShell {
  name = "stc-zensical";

  packages = with pkgs; [
    glow
    pipenv
    pre-commit
    python312
    python312Packages.pip
    rumdl
  ];

  shellHook = ''
    echo "[stc:zensical] Operational. The documentation cogitator awakens."

    if [ ! -f .pre-commit-config.yaml ]; then
      cp ${preCommitConfig} .pre-commit-config.yaml
      chmod 644 .pre-commit-config.yaml
    fi

    if [ -d .git ] && [ ! -f .git/hooks/pre-commit ]; then
      pre-commit install -f --install-hooks
    fi

    if [ -f Pipfile ]; then
      pipenv install
    else
      echo "  No Pipfile found. Run 'pipenv install zensical' to start."
    fi
  '';
}
