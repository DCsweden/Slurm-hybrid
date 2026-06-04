#!/bin/bash
set -euo pipefail

export SLURM_VERSION="${SLURM_VERSION:-24.05.3}"
export NODE_NAME="${NODE_NAME:-$(hostname -s)}"
export CLOUD_PROVIDER="${CLOUD_PROVIDER:-aws}"
export INSTANCE_ID="${INSTANCE_ID:-}"

# Private compute nodes receive Slurm binaries + munge debs from ctrl1 (no apt/internet).
if [[ ! -x /usr/local/sbin/slurmd ]]; then
  echo "ERROR: /usr/local/sbin/slurmd missing — sync slurm-hybrid-bin.tgz from ctrl1 first" >&2
  exit 1
fi

if [[ "$(hostname -s)" != "$NODE_NAME" ]]; then
  hostnamectl set-hostname "$NODE_NAME" 2>/dev/null || true
  grep -q "$NODE_NAME" /etc/hosts || echo "127.0.1.1 $NODE_NAME" >> /etc/hosts
fi

if [[ ! -f /etc/systemd/system/slurmd.service ]]; then
  cat >/etc/systemd/system/slurmd.service <<'UNIT'
[Unit]
Description=Slurm node daemon
After=munge.service network-online.target

[Service]
ExecStart=/usr/local/sbin/slurmd -f /etc/slurm/slurm.conf
User=root
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
fi

if ! systemctl is-active --quiet munge; then
  systemctl enable munge
  systemctl start munge
fi

systemctl enable slurmd
systemctl restart slurmd

echo "Compute $NODE_NAME ($CLOUD_PROVIDER) bootstrap complete"
