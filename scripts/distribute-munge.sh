#!/bin/bash
# Distribute Munge key from ctrl1 to all Slurm nodes
set -euo pipefail

KEY="${SSH_KEY:-${KEY:-${HOME}/.ssh/cluster_key}}"
KEY="${KEY/#\~/$HOME}"
CTRL1_IP="${CTRL1_IP:-16.16.58.152}"
CTRL1="slurmadmin@${CTRL1_IP}"

LOGIN_IP="${LOGIN_IP:-13.49.245.182}"
CTRL2_IP="${CTRL2_IP:-51.20.81.87}"
AWS_COMPUTE_IP="${AWS_COMPUTE_IP:-10.0.2.10}"
[[ -n "${AWS_COMPUTE_IP// }" ]] || AWS_COMPUTE_IP=10.0.2.10
GCP_COMPUTE_IP="${GCP_COMPUTE_IP:-10.1.1.10}"

CLUSTER_KEY='/home/slurmadmin/.ssh/id_cluster'

# Unique targets (public + private duplicates skipped)
ALL_IPS=("$LOGIN_IP" "$CTRL1_IP" "$CTRL2_IP" "$AWS_COMPUTE_IP" "$GCP_COMPUTE_IP")

install_munge_offline() {
  local ip="$1"
  run_ctrl1 "scp -i ${CLUSTER_KEY} -o StrictHostKeyChecking=no /tmp/libmunge2*.deb /tmp/munge*.deb slurmadmin@${ip}:/tmp/ 2>/dev/null" || return 1
  run_host "$ip" 'sudo dpkg -i /tmp/libmunge2*.deb /tmp/munge*.deb'
}

run_ctrl1() {
  ssh -i "$KEY" -o StrictHostKeyChecking=no "$CTRL1" "$@"
}

is_private_ip() {
  [[ "$1" =~ ^10\. ]] || [[ "$1" =~ ^192\.168\. ]] || [[ "$1" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]
}

run_host() {
  local ip="$1"
  shift
  local remote_cmd
  printf -v remote_cmd '%q ' "$@"
  if [[ "$ip" == "$GCP_COMPUTE_IP" ]]; then
    return 1
  fi
  if is_private_ip "$ip"; then
    run_ctrl1 "ssh -i ${CLUSTER_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=30 slurmadmin@${ip} ${remote_cmd}"
  else
    ssh -i "$KEY" -o StrictHostKeyChecking=no "slurmadmin@${ip}" "$@"
  fi
}

echo "==> Prepare munge debs on ctrl1 (for offline nodes)"
run_ctrl1 'cd /tmp && apt-get download -qq libmunge2 munge 2>/dev/null || true'

install_munge_host() {
  local ip="$1"
  echo "  munge @ $ip"
  run_host "$ip" 'sudo chown root:root / /etc /usr /opt 2>/dev/null; sudo chmod 755 / /etc /usr /opt 2>/dev/null; true'
  if ! run_host "$ip" 'sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq munge' 2>/dev/null; then
    install_munge_offline "$ip" || true
  fi
  run_host "$ip" 'sudo systemctl stop munge 2>/dev/null || true' || true
}

for ip in "${ALL_IPS[@]}"; do
  [[ "$ip" == "$GCP_COMPUTE_IP" ]] && continue
  install_munge_host "$ip" || true
done

echo "==> Munge key on ctrl1"
run_ctrl1 'sudo chown root:root / /etc /usr /opt 2>/dev/null; sudo chmod 755 / /etc /usr /opt 2>/dev/null; true
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq munge
if [[ ! -f /etc/munge/munge.key ]]; then
  sudo create-munge-key 2>/dev/null || sudo dd if=/dev/urandom bs=1 count=1024 of=/etc/munge/munge.key status=none
  sudo chown munge:munge /etc/munge/munge.key
  sudo chmod 400 /etc/munge/munge.key
fi
sudo systemctl enable --now munge'

deploy_key() {
  local ip="$1"
  echo "  key -> $ip"
  run_ctrl1 "scp -i ${CLUSTER_KEY} -o StrictHostKeyChecking=no /tmp/munge.key.sync slurmadmin@${ip}:/tmp/munge.key"
  run_host "$ip" 'sudo install -o munge -g munge -m 400 /tmp/munge.key /etc/munge/munge.key
    rm -f /tmp/munge.key
    sudo systemctl enable --now munge'
}

run_ctrl1 'sudo cp /etc/munge/munge.key /tmp/munge.key.sync && sudo chown slurmadmin:slurmadmin /tmp/munge.key.sync && chmod 600 /tmp/munge.key.sync'

for ip in "${ALL_IPS[@]}"; do
  [[ "$ip" == "$CTRL1_IP" || "$ip" == "$GCP_COMPUTE_IP" ]] && continue
  deploy_key "$ip"
done

REF=$(run_ctrl1 'sudo md5sum /etc/munge/munge.key | awk "{print \$1}"')
echo "  ctrl1 md5: $REF"
for ip in "${ALL_IPS[@]}"; do
  [[ "$ip" == "$CTRL1_IP" || "$ip" == "$GCP_COMPUTE_IP" ]] && continue
  md5=$(run_host "$ip" 'sudo md5sum /etc/munge/munge.key | awk "{print \$1}"')
  st=$(run_host "$ip" 'sudo systemctl is-active munge')
  [[ "$md5" == "$REF" && "$st" == "active" ]] && echo "  $ip OK" || { echo "  $ip FAIL"; exit 1; }
done
echo "Munge sync done (GCP handled in bootstrap-cluster)."
