#!/bin/bash
# Deploy Munge + Slurm to a compute node from packages on ctrl1 (same flow for AWS and GCP).
# Both nodes are reached via ctrl1 SSH hop over the hybrid VPN (no IAP/gcloud required).
# Usage: deploy-compute-node.sh aws <private-ip>  |  deploy-compute-node.sh gcp
set -euo pipefail

KEY="${SSH_KEY:-${HOME}/.ssh/cluster_key}"
KEY="${KEY/#\~/$HOME}"
CTRL1_IP="${CTRL1_IP:?set CTRL1_IP}"
CTRL1="slurmadmin@${CTRL1_IP}"
CLUSTER_KEY='/home/slurmadmin/.ssh/id_cluster'
MODE="${1:?usage: deploy-compute-node.sh aws|gcp [ip]}"
TARGET_IP="${2:-}"
GCP_COMPUTE_IP="${GCP_COMPUTE_IP:-10.1.1.10}"
SLURM_VERSION="${SLURM_VERSION:-24.05.3}"
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
    INSTANCE_ID="${GCP_INSTANCE:-gcp-compute}"
    TARGET_IP="${GCP_COMPUTE_IP}"
    ;;
  *) echo "unknown mode: $MODE" >&2; exit 1 ;;
esac

wait_compute_ssh() {
  echo "==> Wait for SSH to ${NODE_NAME} (${TARGET_IP}) via ctrl1"
  for i in $(seq 1 36); do
    if run_ctrl1 "ssh -i ${CLUSTER_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=5 slurmadmin@${TARGET_IP} echo ok" 2>/dev/null; then
      echo "  ready"
      return 0
    fi
    if (( i % 6 == 0 )); then echo "  still waiting (${i}/36) — VPN or startup?" >&2; fi
    sleep 10
  done
  echo "Timeout: ctrl1 cannot SSH to ${TARGET_IP}" >&2
  return 1
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

wait_compute_ssh

echo "==> Deploy -> ${NODE_NAME} (${TARGET_IP})"
"${SCP[@]}" "$WORK/compute-bundle.tgz" "${CTRL1}:/tmp/compute-bundle.tgz"
run_ctrl1 "scp -i ${CLUSTER_KEY} -o StrictHostKeyChecking=no /tmp/compute-bundle.tgz slurmadmin@${TARGET_IP}:/tmp/"
run_ctrl1 "ssh -i ${CLUSTER_KEY} -o StrictHostKeyChecking=no slurmadmin@${TARGET_IP}" <<REMOTE
set -euo pipefail
sudo rm -rf /tmp/slurm-compute-bundle && sudo mkdir -p /tmp/slurm-compute-bundle
sudo tar xzf /tmp/compute-bundle.tgz -C /tmp/slurm-compute-bundle
export NODE_NAME='${NODE_NAME}' CLOUD_PROVIDER='${CLOUD_PROVIDER}' INSTANCE_ID='${INSTANCE_ID}' SLURM_VERSION='${SLURM_VERSION}'
sudo -E bash /tmp/slurm-compute-bundle/install.sh
REMOTE

echo "  ${NODE_NAME} OK"
