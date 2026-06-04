#!/bin/bash
set -euo pipefail

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y munge slurm-wlm 2>/dev/null || true

# Client-only: install Slurm user tools matching cluster version
if [[ ! -x /opt/slurm-hybrid/install-slurm.sh ]]; then
  curl -fsSL -o /opt/slurm-hybrid/install-slurm.sh https://download.schedmd.com/slurm/slurm-24.05.3.tar.bz2 2>/dev/null || true
fi

# Prefer copying munge.key from ctrl1: ssh ctrl1 sudo cat /etc/munge/munge.key
systemctl enable munge || true

echo "Login node ready — copy /etc/munge/munge.key from ctrl1 and run: systemctl start munge"
