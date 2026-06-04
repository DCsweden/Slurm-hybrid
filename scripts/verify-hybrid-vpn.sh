#!/bin/bash
# Print hybrid VPN status (AWS + GCP). Run from laptop with aws + gcloud ADC.
set -euo pipefail

PROJECT="${GCP_PROJECT:-dcprod}"
REGION="${GCP_REGION:-europe-north2}"
NAME="${CLUSTER_NAME:-slurm-hybrid}"

echo "==> AWS VPN ($NAME-vpn-gcp)"
aws ec2 describe-vpn-connections \
  --filters "Name=tag:Name,Values=${NAME}-vpn-gcp" \
  --query 'VpnConnections[0].{State:State,Routes:Routes[*].DestinationCidrBlock,VgwTelemetry:VgwTelemetry[*].{Ip:OutsideIpAddress,Status:Status,Msg:StatusMessage}}' \
  --output table 2>/dev/null || echo "  (aws cli failed)"

echo "==> GCP VPN tunnel ($NAME-aws-tunnel1)"
gcloud compute vpn-tunnels describe "${NAME}-aws-tunnel1" \
  --project="$PROJECT" --region="$REGION" \
  --format='table(name,status,detailedStatus,peerIp)' 2>/dev/null || echo "  (tunnel missing)"

echo "==> GCP route to AWS"
gcloud compute routes describe "${NAME}-to-aws" --project="$PROJECT" \
  --format='table(name,destRange,priority,nextHopVpnTunnel)' 2>/dev/null || echo "  (route missing)"

echo "==> From gcp-compute (IAP): ping ctrl1"
gcloud compute ssh "slurmadmin@gcp-compute" --project="$PROJECT" --zone="${GCP_ZONE:-europe-north2-a}" \
  --tunnel-through-iap --quiet --command='ping -c2 -W2 10.0.1.11 || true' 2>/dev/null | tail -5 || true
