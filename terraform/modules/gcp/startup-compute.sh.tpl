#!/bin/bash
# Minimal GCP compute startup — Slurm/Munge installed by deploy-compute-node.sh (same as AWS).
set -euo pipefail

hostnamectl set-hostname ${node_name}
grep -q "${node_name}" /etc/hosts || echo "127.0.1.1 ${node_name}" >> /etc/hosts
install -d -m 755 /opt/slurm-hybrid /etc/slurm
