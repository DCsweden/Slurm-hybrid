#!/bin/bash
# Deploy Munge + Slurm to a compute node from packages on ctrl1 (same flow for AWS and GCP).
# Usage: deploy-compute-node.sh aws <private-ip>  |  deploy-compute-node.sh gcp
set -euo pipefail

KEY="${SSH_KEY:-${HOME}/.ssh/cluster_key}"
KEY="${KEY/#\~/$HOME}"
CTRL1_IP="${CTRL1_IP:?set CTRL1_IP}"
CTRL1="slurmadmin@${CTRL1_IP}"
CLUSTER_KEY='/home/slurmadmin/.ssh/id_cluster'
MODE="${1:?usage: deploy-compute-node.sh aws|gcp [ip]}"
TARGET_IP="${2:-}"
GCP_PROJECT="${GCP_PROJECT:-dcprod}"
GCP_ZONE="${GCP_ZONE:-europe-north2-a}"
GCP_INSTANCE="${GCP_INSTANCE:-gcp-compute}"
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
    INSTANCE_ID="${GCP_INSTANCE}"
    ;;
  *) echo "unknown mode: $MODE" >&2; exit 1 ;;
esac

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

if [[ "$MODE" == aws ]]; then
  echo "==> Deploy -> aws-compute (${TARGET_IP})"
  "${SCP[@]}" "$WORK/compute-bundle.tgz" "${CTRL1}:/tmp/compute-bundle.tgz"
  run_ctrl1 "scp -i ${CLUSTER_KEY} -o StrictHostKeyChecking=no /tmp/compute-bundle.tgz slurmadmin@${TARGET_IP}:/tmp/"
  run_ctrl1 "ssh -i ${CLUSTER_KEY} -o StrictHostKeyChecking=no slurmadmin@${TARGET_IP}" <<REMOTE
set -euo pipefail
sudo rm -rf /tmp/slurm-compute-bundle && sudo mkdir -p /tmp/slurm-compute-bundle
sudo tar xzf /tmp/compute-bundle.tgz -C /tmp/slurm-compute-bundle
export NODE_NAME='${NODE_NAME}' CLOUD_PROVIDER='${CLOUD_PROVIDER}' INSTANCE_ID='${INSTANCE_ID}' SLURM_VERSION='${SLURM_VERSION}'
sudo -E bash /tmp/slurm-compute-bundle/install.sh
REMOTE

elif [[ "$MODE" == gcp ]]; then
  echo "==> Deploy -> gcp-compute (${GCP_INSTANCE})"
  gcloud compute scp --project="$GCP_PROJECT" --zone="$GCP_ZONE" --tunnel-through-iap \
    "$WORK/compute-bundle.tgz" "${GCP_INSTANCE}:/tmp/compute-bundle.tgz"
  gcloud compute ssh "$GCP_INSTANCE" --project="$GCP_PROJECT" --zone="$GCP_ZONE" \
    --tunnel-through-iap --command="
set -euo pipefail
sudo rm -rf /tmp/slurm-compute-bundle && sudo mkdir -p /tmp/slurm-compute-bundle
sudo tar xzf /tmp/compute-bundle.tgz -C /tmp/slurm-compute-bundle
export NODE_NAME='${NODE_NAME}' CLOUD_PROVIDER='${CLOUD_PROVIDER}' INSTANCE_ID='${INSTANCE_ID}' SLURM_VERSION='${SLURM_VERSION}'
sudo -E bash /tmp/slurm-compute-bundle/install.sh"
fi

echo "  ${NODE_NAME} OK"
