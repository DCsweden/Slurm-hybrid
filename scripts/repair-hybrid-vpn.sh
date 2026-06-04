#!/bin/bash
# Coordinated refresh of hybrid AWS↔GCP VPN (static IPsec, tunnel1 only).
# Use when IKE shows UP but dataplane fails, or after one-sided manual deletes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="${ROOT}/terraform"
ACTION="${1:-plan}"

cd "$TF_DIR"

case "$ACTION" in
  plan)
    terraform init -input=false
    terraform plan -input=false \
      -target=aws_customer_gateway.gcp \
      -target=aws_vpn_gateway_attachment.main \
      -target=aws_vpn_connection.gcp \
      -target=aws_vpn_connection_route.gcp_cidr \
      -target=module.gcp.google_compute_vpn_tunnel.aws \
      -target=module.gcp.google_compute_route.aws_via_vpn
    ;;
  apply)
    terraform init -input=false
    terraform apply -input=false -auto-approve \
      -target=aws_customer_gateway.gcp \
      -target=aws_vpn_gateway_attachment.main \
      -target=aws_vpn_connection.gcp \
      -target=aws_vpn_connection_route.gcp_cidr \
      -target=module.gcp.google_compute_vpn_tunnel.aws \
      -target=module.gcp.google_compute_route.aws_via_vpn
    echo "==> Verify"
    "${ROOT}/scripts/verify-hybrid-vpn.sh"
    ;;
  *)
    echo "Usage: $0 [plan|apply]" >&2
    exit 1
    ;;
esac
