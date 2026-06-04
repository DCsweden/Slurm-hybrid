#!/bin/bash
# Fix slurmadmin authorized_keys on nodes where cloud-init did not install the deploy key.
# Uses EC2/GCP default user (ubuntu) which receives the same public key via aws_key_pair / metadata.
set -euo pipefail

KEY="${SSH_KEY:-${HOME}/.ssh/slurm_deploy}"
KEY="${KEY/#\~/$HOME}"
CTRL1_IP="${CTRL1_IP:?set CTRL1_IP (ctrl1 public IP)}"
PUB="${SSH_PUBLIC_KEY_FILE:-}"

if [[ -z "$PUB" && -n "${SSH_PUBLIC_KEY:-}" ]]; then
  printf '%s\n' "$SSH_PUBLIC_KEY" > /tmp/slurm-pubkey
  PUB=/tmp/slurm-pubkey
fi
if [[ -z "$PUB" ]]; then
  PUB=$(mktemp)
  ssh-keygen -y -f "$KEY" > "$PUB"
fi

SSH=(ssh -i "$KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=20)
CTRL1="slurmadmin@${CTRL1_IP}"

PRIVATE_IPS="${PRIVATE_IPS:-10.0.1.10 10.0.1.12 10.0.2.10}"

CLUSTER_KEY='/home/slurmadmin/.ssh/id_cluster'

install_key_ubuntu() {
  local ip="$1"
  local pub_line
  pub_line=$(head -1 "$PUB")
  "${SSH[@]}" "$CTRL1" "ssh -i ${CLUSTER_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=15 ubuntu@${ip} bash -s" <<REMOTE || return 1
set -e
PUB_LINE='${pub_line//\'/\'\\\'\'}'
install -d -m 700 -o slurmadmin -g slurmadmin /home/slurmadmin/.ssh
touch /home/slurmadmin/.ssh/authorized_keys
grep -qxF "\$PUB_LINE" /home/slurmadmin/.ssh/authorized_keys 2>/dev/null || echo "\$PUB_LINE" >> /home/slurmadmin/.ssh/authorized_keys
chown slurmadmin:slurmadmin /home/slurmadmin/.ssh/authorized_keys
chmod 600 /home/slurmadmin/.ssh/authorized_keys
REMOTE
}

install_key_slurmadmin() {
  local ip="$1"
  local pub_line
  pub_line=$(head -1 "$PUB")
  "${SSH[@]}" "$CTRL1" "ssh -i ${CLUSTER_KEY} -o StrictHostKeyChecking=no slurmadmin@${ip} bash -s" <<REMOTE
set -e
PUB_LINE='${pub_line//\'/\'\\\'\'}'
install -d -m 700 ~/.ssh
touch ~/.ssh/authorized_keys
grep -qxF "\$PUB_LINE" ~/.ssh/authorized_keys 2>/dev/null || echo "\$PUB_LINE" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
REMOTE
}

echo "==> Repair slurmadmin SSH keys (via ctrl1 ${CTRL1_IP})"
for ip in $PRIVATE_IPS; do
  echo "  $ip"
  if install_key_ubuntu "$ip" 2>/dev/null; then
    echo "    fixed via ubuntu@${ip}"
  elif install_key_slurmadmin "$ip" 2>/dev/null; then
    echo "    fixed via slurmadmin@${ip}"
  else
    echo "    FAILED (no ubuntu/slurmadmin access from ctrl1)" >&2
    exit 1
  fi
done

echo "==> Verify slurmadmin login from ctrl1"
for ip in $PRIVATE_IPS; do
  "${SSH[@]}" "$CTRL1" "ssh -i ${CLUSTER_KEY} -o BatchMode=yes slurmadmin@${ip} hostname" && echo "  $ip OK"
done
echo "Done."
