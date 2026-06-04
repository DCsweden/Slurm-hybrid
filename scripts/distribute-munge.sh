#!/bin/bash
# Distribute Munge key from ctrl1 to all Slurm nodes
set -euo pipefail

KEY="${KEY:-$HOME/.ssh/slurm_deploy}"
CTRL1_IP="16.16.58.152"
CTRL1="slurmadmin@${CTRL1_IP}"

ALL_IPS=(
  13.49.245.182   # login
  16.16.58.152    # ctrl1
  51.20.81.87     # ctrl2
  10.0.1.10       # login private
  10.0.1.12       # ctrl2 private
  10.0.2.10       # aws-compute
  10.1.1.10       # gcp-compute
)

needs_jump() {
  case "$1" in
    10.0.*|10.1.*) return 0 ;;
    *) return 1 ;;
  esac
}

ssh_target() {
  local ip="$1"
  shift
  if needs_jump "$ip"; then
    ssh -i "$KEY" -o StrictHostKeyChecking=no -o "ProxyJump=slurmadmin@${CTRL1_IP}" "slurmadmin@${ip}" "$@"
  else
    ssh -i "$KEY" -o StrictHostKeyChecking=no "slurmadmin@${ip}" "$@"
  fi
}

scp_to() {
  local ip="$1" src="$2" dst="$3"
  if needs_jump "$ip"; then
    scp -i "$KEY" -o StrictHostKeyChecking=no -o "ProxyJump=slurmadmin@${CTRL1_IP}" "$src" "slurmadmin@${ip}:${dst}"
  else
    scp -i "$KEY" -o StrictHostKeyChecking=no "$src" "slurmadmin@${ip}:${dst}"
  fi
}

install_munge_host() {
  local ip="$1"
  echo "  install munge @ $ip"
  ssh_target "$ip" 'sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq munge 2>/dev/null || true
    sudo systemctl stop munge 2>/dev/null || true'
}

echo "==> Ensure munge installed on all nodes"
for ip in "${ALL_IPS[@]}"; do install_munge_host "$ip"; done

echo "==> Create/sync key on ctrl1"
ssh -i "$KEY" -o StrictHostKeyChecking=no "$CTRL1" 'if [[ ! -f /etc/munge/munge.key ]]; then
  sudo dd if=/dev/urandom bs=1 count=1024 of=/etc/munge/munge.key status=none
  sudo chown munge:munge /etc/munge/munge.key
  sudo chmod 400 /etc/munge/munge.key
fi
sudo systemctl enable munge
sudo systemctl restart munge
sudo systemctl is-active munge'

KEY_TMP=$(mktemp)
trap 'rm -f "$KEY_TMP"' EXIT
ssh -i "$KEY" -o StrictHostKeyChecking=no "$CTRL1" 'sudo cat /etc/munge/munge.key' > "$KEY_TMP"
chmod 600 "$KEY_TMP"

deploy_key() {
  local ip="$1"
  echo "  deploy key -> $ip"
  scp_to "$ip" "$KEY_TMP" /tmp/munge.key
  ssh_target "$ip" 'sudo install -o munge -g munge -m 400 /tmp/munge.key /etc/munge/munge.key
    rm -f /tmp/munge.key
    sudo systemctl enable munge
    sudo systemctl restart munge
    sudo systemctl is-active munge'
}

echo "==> Distribute key to all nodes (except ctrl1 source)"
for ip in "${ALL_IPS[@]}"; do
  [[ "$ip" == "$CTRL1_IP" ]] && continue
  deploy_key "$ip"
done

echo "==> Verify"
REF=$(ssh -i "$KEY" -o StrictHostKeyChecking=no "$CTRL1" 'sudo md5sum /etc/munge/munge.key | awk "{print \$1}"')
echo "  ctrl1 key md5: $REF"
for ip in "${ALL_IPS[@]}"; do
  [[ "$ip" == "$CTRL1_IP" ]] && continue
  md5=$(ssh_target "$ip" 'sudo md5sum /etc/munge/munge.key | awk "{print \$1}"')
  state=$(ssh_target "$ip" 'sudo systemctl is-active munge')
  if [[ "$md5" == "$REF" && "$state" == "active" ]]; then
    echo "  $ip: OK"
  else
    echo "  $ip: FAIL md5=$md5 state=$state"
    exit 1
  fi
done

echo "Done. Munge key synced from ctrl1 to all nodes."
