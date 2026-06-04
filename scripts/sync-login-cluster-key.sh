#!/bin/bash
# Copy id_cluster from ctrl1 to login (10.0.1.10) so login can SSH to private nodes / GCP over VPN.
# Run from GitHub Actions runner or laptop with SSH_KEY to ctrl1.
set -euo pipefail

KEY="${SSH_KEY:-${HOME}/.ssh/cluster_key}"
KEY="${KEY/#\~/$HOME}"
CTRL1_IP="${CTRL1_IP:?set CTRL1_IP}"
LOGIN_PRIVATE_IP="${LOGIN_PRIVATE_IP:-10.0.1.10}"
CLUSTER_KEY='/home/slurmadmin/.ssh/id_cluster'

SSH=(ssh -i "$KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=30)
CTRL1="slurmadmin@${CTRL1_IP}"

echo "==> Sync id_cluster: ctrl1 -> login (${LOGIN_PRIVATE_IP})"
"${SSH[@]}" "$CTRL1" "ssh -i ${CLUSTER_KEY} -o StrictHostKeyChecking=no slurmadmin@${LOGIN_PRIVATE_IP} 'mkdir -p ~/.ssh && chmod 700 ~/.ssh'"
"${SSH[@]}" "$CTRL1" "scp -i ${CLUSTER_KEY} -o StrictHostKeyChecking=no ${CLUSTER_KEY} slurmadmin@${LOGIN_PRIVATE_IP}:.ssh/id_cluster"
"${SSH[@]}" "$CTRL1" "ssh -i ${CLUSTER_KEY} -o StrictHostKeyChecking=no slurmadmin@${LOGIN_PRIVATE_IP} 'chmod 600 ~/.ssh/id_cluster && test -f ~/.ssh/id_cluster'"
echo "OK — on login: ssh -i ~/.ssh/id_cluster slurmadmin@10.1.1.10"
