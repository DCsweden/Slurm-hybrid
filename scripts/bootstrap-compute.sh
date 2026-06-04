#!/bin/bash
set -euo pipefail

export SLURM_VERSION="${SLURM_VERSION:-24.05.3}"
export NODE_NAME="${NODE_NAME:-$(hostname -s)}"
export CLOUD_PROVIDER="${CLOUD_PROVIDER:-aws}"
export INSTANCE_ID="${INSTANCE_ID:-}"

if [[ -f /opt/slurm-hybrid/install-slurm.sh ]]; then
  bash /opt/slurm-hybrid/install-slurm.sh
fi

systemctl enable munge slurmd
systemctl start munge || true

EXTRA_ARGS=()
if [[ -n "$INSTANCE_ID" ]]; then
  EXTRA_ARGS+=(--instance-id="$INSTANCE_ID")
fi

# Register cloud metadata for accounting (power save guide)
exec /usr/local/sbin/slurmd -f /etc/slurm/slurm.conf "${EXTRA_ARGS[@]}" -N "$NODE_NAME" 2>/dev/null &
systemctl restart slurmd || true

echo "Compute $NODE_NAME ($CLOUD_PROVIDER) bootstrap complete"
