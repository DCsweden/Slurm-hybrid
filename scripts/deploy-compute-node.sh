#!/bin/bash
# Deploy Munge + Slurm to a compute node from packages on ctrl1.
# AWS: ctrl1 SSH hop over hybrid VPN (private IP).
# GCP: try VPN hop first; fall back to gcloud IAP from CI (needs IAP firewall + CI SA role).
set -euo pipefail

KEY="${SSH_KEY:-${HOME}/.ssh/cluster_key}"
KEY="${KEY/#\~/$HOME}"
CTRL1_IP="${CTRL1_IP:?set CTRL1_IP}"
CTRL1="slurmadmin@${CTRL1_IP}"
CLUSTER_KEY='/home/slurmadmin/.ssh/id_cluster'
MODE="${1:?usage: deploy-compute-node.sh aws|gcp [ip]}"
TARGET_IP="${2:-}"
GCP_COMPUTE_IP="${GCP_COMPUTE_IP:-10.1.1.10}"
GCP_PROJECT="${GCP_PROJECT:-dcprod}"
GCP_ZONE="${GCP_ZONE:-europe-north2-a}"
GCP_INSTANCE="${GCP_INSTANCE:-gcp-compute}"
SLURM_VERSION="${SLURM_VERSION:-24.05.3}"
VPN_SSH_ATTEMPTS="${VPN_SSH_ATTEMPTS:-18}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

SSH=(ssh -i "$KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=30)
SCP=(scp -i "$KEY" -o StrictHostKeyChecking=no)

run_ctrl1() { "${SSH[@]}" "$CTRL1" "$@"; }

case "$MODE" in
  aws)
    NODE_NAME="${AWS_COMPUTE_NODE_NAME:-aws-compute}"
    CLOUD_PROVIDER=aws
    INSTANCE_ID="${AWS_COMPUTE_INSTANCE_ID:-}"
    TARGET_IP="${TARGET_IP:?aws mode requires private ip}"
    ;;
  gcp)
    NODE_NAME="${GCP_COMPUTE_NODE_NAME:-gcp-compute}"
    CLOUD_PROVIDER=gcp
    INSTANCE_ID="${GCP_INSTANCE}"
    TARGET_IP="${GCP_COMPUTE_IP}"
    ;;
  *) echo "unknown mode: $MODE" >&2; exit 1 ;;
esac

wait_compute_ssh_via_vpn() {
  echo "==> Wait for SSH to ${NODE_NAME} (${TARGET_IP}) via ctrl1/VPN"
  for i in $(seq 1 "$VPN_SSH_ATTEMPTS"); do
    if run_ctrl1 "ssh -i ${CLUSTER_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=5 slurmadmin@${TARGET_IP} echo ok" 2>/dev/null; then
      echo "  VPN path ready"
      return 0
    fi
    if (( i % 6 == 0 )); then echo "  still waiting (${i}/${VPN_SSH_ATTEMPTS}) — VPN or startup?" >&2; fi
    sleep 10
  done
  return 1
}

deploy_via_vpn() {
  echo "==> Deploy -> ${NODE_NAME} (${TARGET_IP}) via ctrl1"
  "${SCP[@]}" "$WORK/compute-bundle.tgz" "${CTRL1}:/tmp/compute-bundle.tgz"
  run_ctrl1 "scp -i ${CLUSTER_KEY} -o StrictHostKeyChecking=no /tmp/compute-bundle.tgz slurmadmin@${TARGET_IP}:/tmp/"
  run_ctrl1 "ssh -i ${CLUSTER_KEY} -o StrictHostKeyChecking=no slurmadmin@${TARGET_IP}" <<REMOTE
set -euo pipefail
sudo rm -rf /tmp/slurm-compute-bundle && sudo mkdir -p /tmp/slurm-compute-bundle
sudo tar xzf /tmp/compute-bundle.tgz -C /tmp/slurm-compute-bundle
export NODE_NAME='${NODE_NAME}' CLOUD_PROVIDER='${CLOUD_PROVIDER}' INSTANCE_ID='${INSTANCE_ID}' SLURM_VERSION='${SLURM_VERSION}'
sudo -E bash /tmp/slurm-compute-bundle/install.sh
REMOTE
}

deploy_via_iap() {
  if ! command -v gcloud >/dev/null 2>&1; then
    echo "gcloud not available for IAP fallback" >&2
    return 1
  fi
  echo "==> Deploy -> ${NODE_NAME} (${GCP_INSTANCE}) via IAP (cluster SSH key)"
  local scp_flags=(--tunnel-through-iap --project="$GCP_PROJECT" --zone="$GCP_ZONE"
    --ssh-key-file="$KEY" --scp-flag="-l slurmadmin -o StrictHostKeyChecking=no")
  local ssh_flags=(--tunnel-through-iap --project="$GCP_PROJECT" --zone="$GCP_ZONE"
    --ssh-key-file="$KEY" --ssh-flag="-l slurmadmin -o StrictHostKeyChecking=no")

  gcloud compute scp "${scp_flags[@]}" \
    "$WORK/compute-bundle.tgz" "${GCP_INSTANCE}:/tmp/compute-bundle.tgz"
  gcloud compute ssh "${ssh_flags[@]}" "$GCP_INSTANCE" --command="
set -euo pipefail
sudo rm -rf /tmp/slurm-compute-bundle && sudo mkdir -p /tmp/slurm-compute-bundle
sudo tar xzf /tmp/compute-bundle.tgz -C /tmp/slurm-compute-bundle
export NODE_NAME='${NODE_NAME}' CLOUD_PROVIDER='${CLOUD_PROVIDER}' INSTANCE_ID='${INSTANCE_ID}' SLURM_VERSION='${SLURM_VERSION}'
sudo -E bash /tmp/slurm-compute-bundle/install.sh"
}

log_vpn_diagnostics() {
  echo "==> VPN diagnostics (for manual follow-up)" >&2
  if command -v aws >/dev/null 2>&1; then
    aws ec2 describe-vpn-connections \
      --filters "Name=tag:Name,Values=${CLUSTER_NAME:-slurm-hybrid}-vpn-gcp" \
      --query 'VpnConnections[0].{State:State,VgwTelemetry:VgwTelemetry[*].{OutsideIp:OutsideIpAddress,Status:Status,Message:StatusMessage}}' \
      --output table 2>/dev/null || true
  fi
  if command -v gcloud >/dev/null 2>&1; then
    gcloud compute vpn-tunnels list --project="$GCP_PROJECT" --regions="${GCP_ZONE%-*}" \
      --format='table(name,status,detailedStatus,peerIp)' 2>/dev/null || true
  fi
  run_ctrl1 "ping -c 2 -W 3 ${TARGET_IP} 2>&1 || true; ip route get ${TARGET_IP} 2>&1 || true" 2>/dev/null || true
}

echo "==> Prepare packages on ctrl1"
run_ctrl1 'bash -s' <<'REMOTE'
set -euo pipefail
cd /tmp
apt-get download -qq libmunge2 munge 2>/dev/null || true
sudo tar czf /tmp/slurm-hybrid-bin.tgz -C /usr/local bin sbin libexec lib 2>/dev/null || true
sudo tar czf /tmp/slurm-hybrid-units.tgz -C / etc/systemd/system/slurmd.service 2>/dev/null || true
sudo cp /etc/munge/munge.key /tmp/munge.key.sync
sudo chown slurmadmin:slurmadmin /tmp/munge.key.sync
chmod 600 /tmp/munge.key.sync
tar czf /tmp/compute-prep.tgz libmunge2*.deb munge*.deb slurm-hybrid-bin.tgz slurm-hybrid-units.tgz munge.key.sync
REMOTE

echo "==> Assemble compute bundle"
BUNDLE="$WORK/bundle"
mkdir -p "$BUNDLE/assets/etc/slurm" "$BUNDLE/assets/opt/slurm-hybrid" "$BUNDLE/assets/usr/sbin"
cp "$REPO_ROOT/slurm/"*.conf "$BUNDLE/assets/etc/slurm/"
cp "$REPO_ROOT/scripts/bootstrap-compute.sh" "$BUNDLE/assets/opt/slurm-hybrid/"
cp "$REPO_ROOT/scripts/slurm_resume" "$REPO_ROOT/scripts/slurm_suspend" \
   "$REPO_ROOT/scripts/slurm_resume_fail" "$BUNDLE/assets/usr/sbin/"
chmod +x "$BUNDLE/assets/opt/slurm-hybrid/"*.sh "$BUNDLE/assets/usr/sbin/"*
tar czf "$BUNDLE/slurm-hybrid-assets.tgz" -C "$BUNDLE/assets" etc opt usr

"${SCP[@]}" "${CTRL1}:/tmp/compute-prep.tgz" "$WORK/"
tar xzf "$WORK/compute-prep.tgz" -C "$BUNDLE"
mv "$BUNDLE/munge.key.sync" "$BUNDLE/munge.key"
cp "$REPO_ROOT/scripts/compute-node-install.remote.sh" "$BUNDLE/install.sh"
chmod +x "$BUNDLE/install.sh"
tar czf "$WORK/compute-bundle.tgz" -C "$BUNDLE" .

if [[ "$MODE" == aws" ]]; then
  wait_compute_ssh_via_vpn || { log_vpn_diagnostics; exit 1; }
  deploy_via_vpn
elif [[ "$MODE" == gcp" ]]; then
  if wait_compute_ssh_via_vpn; then
    deploy_via_vpn
  else
    echo "WARN: VPN SSH to ${TARGET_IP} timed out — trying IAP fallback" >&2
    log_vpn_diagnostics
    deploy_via_iap || { echo "GCP deploy failed (VPN and IAP)" >&2; exit 1; }
  fi
fi

echo "  ${NODE_NAME} OK"
