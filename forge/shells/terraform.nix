# Forge Shell: Terraform
#
# Infrastructure as Code environment. Includes:
#   terraform       — the main tool
#   terragrunt      — DRY wrapper for multi-env deployments
#   terraform-docs  — auto-generate module documentation
#   tflint          — linting (catches deprecated syntax, type errors)
#   tfsec           — static security analysis
#   just            — task runner (replaces Makefile for common operations)
#   glow            — render markdown docs in the terminal
{ pkgs, preCommitConfig }:

pkgs.mkShell {
  name = "stc-terraform";

  packages = with pkgs; [
    glow
    just
    pre-commit
    terraform
    terraform-docs
    terragrunt
    tflint
    tfsec
  ];

  shellHook = ''
    echo "[stc:terraform] Operational. Infrastructure awaits."
    echo "  terraform    $(terraform version -json | ${pkgs.jq}/bin/jq -r '.terraform_version')"
    echo "  terragrunt   $(terragrunt --version | head -1)"

    if [ ! -f .pre-commit-config.yaml ]; then
      cp ${preCommitConfig} .pre-commit-config.yaml
      chmod 644 .pre-commit-config.yaml
    fi

    if [ -d .git ] && [ ! -f .git/hooks/pre-commit ]; then
      pre-commit install -f --install-hooks
    fi
  '';
}
