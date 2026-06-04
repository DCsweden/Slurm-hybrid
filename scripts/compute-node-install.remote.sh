#!/bin/bash
# Runs on a compute node (AWS or GCP). Expects /tmp/slurm-compute-bundle/extracted/.
set -euo pipefail

BUNDLE=/tmp/slurm-compute-bundle
cd "$BUNDLE"

: "${NODE_NAME:?NODE_NAME required}"
: "${CLOUD_PROVIDER:?CLOUD_PROVIDER required}"
INSTANCE_ID="${INSTANCE_ID:-}"

echo "==> Munge"
dpkg -i ./libmunge2*.deb ./munge*.deb
install -o munge -g munge -m 400 ./munge.key /etc/munge/munge.key
systemctl enable --now munge

echo "==> Slurm configs and scripts"
STAGING=$(mktemp -d)
tar xzf ./slurm-hybrid-assets.tgz -C "$STAGING"
install -d -m 755 /etc/slurm /opt/slurm-hybrid /usr/sbin
cp -r --no-preserve=ownership "$STAGING/etc/slurm/." /etc/slurm/
cp -r --no-preserve=ownership "$STAGING/opt/slurm-hybrid/." /opt/slurm-hybrid/
cp -r --no-preserve=ownership "$STAGING/usr/sbin/." /usr/sbin/
chown root:root /etc/slurm && chmod 755 /etc/slurm
chmod 644 /etc/slurm/slurm.conf /etc/slurm/cgroup.conf 2>/dev/null || true
chmod +x /opt/slurm-hybrid/*.sh /usr/sbin/slurm_*
rm -rf "$STAGING"

echo "==> Slurm binaries"
tar xzf ./slurm-hybrid-bin.tgz -C /usr/local
ldconfig
tar xzf ./slurm-hybrid-units.tgz -C /
systemctl daemon-reload

export SLURM_VERSION="${SLURM_VERSION:-24.05.3}"
export NODE_NAME CLOUD_PROVIDER INSTANCE_ID
bash /opt/slurm-hybrid/bootstrap-compute.sh

systemctl is-active munge slurmd
echo "Compute $NODE_NAME ($CLOUD_PROVIDER) ready"
