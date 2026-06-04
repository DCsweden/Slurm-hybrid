#!/bin/bash
# One-time: create AWS OIDC + GCP WIF for GitHub Actions (run with local AWS + gcloud ADC)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/terraform/bootstrap-ci"

echo "==> Bootstrap CI auth (OIDC + Workload Identity Federation)"
echo "    Requires: ~/.aws/credentials (default) + gcloud ADC for project dcprod"
echo ""

if [[ ! -f terraform.tfvars ]]; then
  cp terraform.tfvars.example terraform.tfvars
  echo "Created terraform.tfvars from example — edit if needed."
fi

terraform init -input=false
terraform apply

echo ""
terraform output -raw github_variables_setup
