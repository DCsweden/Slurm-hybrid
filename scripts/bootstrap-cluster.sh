#!/bin/bash
# Full Slurm cluster bootstrap — run from GitHub Actions after terraform apply
set -euo pipefail

KEY="${SSH_KEY:-${HOME}/.ssh/cluster_key}"
# Expand ~ if passed from workflow
KEY="${KEY/#\~/$HOME}"
if [[ ! -f "$KEY" ]]; then
  echo "SSH key not found: $KEY" >&2
  exit 1
fi
SSH=(ssh -i "$KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=30)
SCP=(scp -i "$KEY" -o StrictHostKeyChecking=no)
CLUSTER_KEY='/home/slurmadmin/.ssh/id_cluster'

: "${CTRL1_IP:?CTRL1_IP required}"
: "${CTRL2_IP:?CTRL2_IP required}"
: "${LOGIN_IP:?LOGIN_IP required}"
: "${AWS_COMPUTE_IP:=10.0.2.10}"
[[ -n "${AWS_COMPUTE_IP// }" ]] || AWS_COMPUTE_IP=10.0.2.10
: "${GCP_COMPUTE_IP:=10.1.1.10}"
: "${GCP_ZONE:=europe-north2-a}"
: "${GCP_PROJECT:=dcprod}"
: "${GCP_INSTANCE:=gcp-compute}"
: "${SLURM_VERSION:=24.05.3}"
: "${CLUSTER_NAME:=slurm-hybrid}"

CTRL1="slurmadmin@${CTRL1_IP}"
CTRL2="slurmadmin@${CTRL2_IP}"
LOGIN="slurmadmin@${LOGIN_IP}"

LOGIN_REACHABLE=false

try_ssh_user() {
  local ip="$1"
  local user="$2"
  "${SSH[@]}" "${user}@${ip}" 'echo ready' 2>/dev/null
}

wait_ssh_any() {
  local ip="$1"
  local optional="${2:-false}"
  echo "Waiting for SSH: ${ip}"
  for i in $(seq 1 60); do
    for user in slurmadmin ubuntu; do
      if try_ssh_user "$ip" "$user"; then
        echo "  ready (${user}@${ip})"
        return 0
      fi
    done
    if (( i % 6 == 0 )); then echo "  still waiting (${i}/60)..."; fi
    sleep 10
  done
  if [[ "$optional" == true ]]; then
    echo "WARN: ${ip} not reachable yet"
    return 1
  fi
  echo "Timeout waiting for ${ip}" >&2
  exit 1
}

wait_ssh_slurmadmin() {
  local ip="$1"
  echo "Waiting for slurmadmin@${ip}"
  for i in $(seq 1 30); do
    if try_ssh_user "$ip" slurmadmin; then
      echo "  ready (slurmadmin@${ip})"
      return 0
    fi
    if (( i % 3 == 0 )); then echo "  still waiting (${i}/30)..."; fi
    sleep 10
  done
  echo "Timeout waiting for slurmadmin@${ip}" >&2
  exit 1
}

run_login() {
  if [[ "$LOGIN_REACHABLE" != true ]]; then
    echo "SKIP login: not reachable" >&2
    return 0
  fi
  if is_private_ip "$LOGIN_IP"; then
    local remote_cmd
    printf -v remote_cmd '%q ' "$@"
    run_ctrl1 "ssh -i ${CLUSTER_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=30 slurmadmin@${LOGIN_IP} ${remote_cmd}"
    return $?
  fi
  "${SSH[@]}" "$LOGIN" "$@"
}

scp_to_host() {
  local ip="$1"
  local src="$2"
  local dest="$3"
  "${SCP[@]}" "$src" "slurmadmin@${ip}:${dest}"
}

remote_asset_path() {
  echo "/tmp/slurm-hybrid-assets.tgz"
}

echo "==> Wait for controllers (ubuntu or slurmadmin)"
wait_ssh_any "$CTRL1_IP"
wait_ssh_any "$CTRL2_IP"

echo "==> Repair node access (cloud-init / filesystem)"
export SSH_KEY="$KEY"
for ip in "$CTRL1_IP" "$CTRL2_IP"; do
  bash "$(dirname "$0")/fix-node-access.sh" "$ip"
done
wait_ssh_slurmadmin "$CTRL1_IP"
wait_ssh_slurmadmin "$CTRL2_IP"

run_ctrl1() {
  "${SSH[@]}" "$CTRL1" "$@"
}

is_private_ip() {
  [[ "$1" =~ ^10\. ]] || [[ "$1" =~ ^192\.168\. ]] || [[ "$1" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]
}

run_host() {
  local ip="$1"
  shift
  if [[ "$ip" == "$LOGIN_IP" ]] && [[ "$LOGIN_REACHABLE" == true ]]; then
    run_login "$@"
    return $?
  fi
  local remote_cmd
  printf -v remote_cmd '%q ' "$@"
  if is_private_ip "$ip"; then
    run_ctrl1 "ssh -i ${CLUSTER_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=30 slurmadmin@${ip} ${remote_cmd}"
  else
    "${SSH[@]}" "slurmadmin@${ip}" "$@"
  fi
}

echo "==> Install cluster SSH key on ctrl1 for internal hops"
run_ctrl1 'mkdir -p ~/.ssh && chmod 700 ~/.ssh'
"${SCP[@]}" "$KEY" "${CTRL1}:.ssh/id_cluster"
run_ctrl1 'chmod 600 ~/.ssh/id_cluster'

echo "==> Wait for login (optional — may need new instance from Terraform)"
if wait_ssh_any "$LOGIN_IP" true; then
  LOGIN_REACHABLE=true
  bash "$(dirname "$0")/fix-node-access.sh" "$LOGIN_IP"
  wait_ssh_slurmadmin "$LOGIN_IP"
elif run_ctrl1 "ssh -i ${CLUSTER_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=15 ubuntu@10.0.1.10 echo ok" 2>/dev/null; then
  echo "  login reachable via private 10.0.1.10 — using ctrl1 hop"
  LOGIN_REACHABLE=true
  LOGIN_IP=10.0.1.10
  run_ctrl1 "ssh -i ${CLUSTER_KEY} -o StrictHostKeyChecking=no ubuntu@10.0.1.10 sudo bash -s" <<'REMOTE'
set -e
if [[ "$(stat -c '%a' /)" != "755" ]]; then chmod 755 / && chown root:root /; fi
passwd -d slurmadmin >/dev/null 2>&1 || true
grep -q "$(hostname)" /etc/hosts || echo "127.0.1.1 $(hostname)" >> /etc/hosts
REMOTE
  run_ctrl1 "ssh -i ${CLUSTER_KEY} -o BatchMode=yes slurmadmin@10.0.1.10 echo ready"
fi

echo "==> Install cluster SSH key on login (from ctrl1, for hops to 10.0.x / 10.1.x)"
run_ctrl1 "ssh -i ${CLUSTER_KEY} -o StrictHostKeyChecking=no slurmadmin@10.0.1.10 'mkdir -p ~/.ssh && chmod 700 ~/.ssh'" 2>/dev/null || true
run_ctrl1 "scp -i ${CLUSTER_KEY} -o StrictHostKeyChecking=no /home/slurmadmin/.ssh/id_cluster slurmadmin@10.0.1.10:.ssh/id_cluster" 2>/dev/null || true
run_ctrl1 "ssh -i ${CLUSTER_KEY} -o StrictHostKeyChecking=no slurmadmin@10.0.1.10 'chmod 600 ~/.ssh/id_cluster'" 2>/dev/null || true
if [[ "$LOGIN_REACHABLE" == true && "$LOGIN_IP" != "10.0.1.10" ]]; then
  run_login 'mkdir -p ~/.ssh && chmod 700 ~/.ssh'
  "${SCP[@]}" "$KEY" "${LOGIN}:.ssh/id_cluster"
  run_login 'chmod 600 ~/.ssh/id_cluster'
fi

echo "==> Sync Slurm configs and scripts from repo"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGING=$(mktemp -d)
mkdir -p "$STAGING/etc/slurm" "$STAGING/opt/slurm-hybrid" "$STAGING/usr/sbin"
cp "$REPO_ROOT/slurm/"*.conf "$STAGING/etc/slurm/"
cp "$REPO_ROOT/scripts/install-slurm.sh" \
   "$REPO_ROOT/scripts/bootstrap-controller.sh" \
   "$REPO_ROOT/scripts/bootstrap-login.sh" \
   "$REPO_ROOT/scripts/bootstrap-compute.sh" \
   "$STAGING/opt/slurm-hybrid/"
cp "$REPO_ROOT/scripts/slurm_resume" \
   "$REPO_ROOT/scripts/slurm_suspend" \
   "$REPO_ROOT/scripts/slurm_resume_fail" \
   "$STAGING/usr/sbin/"
chmod +x "$STAGING/opt/slurm-hybrid/"*.sh "$STAGING/usr/sbin/"*
tar czf /tmp/slurm-hybrid-assets.tgz -C "$STAGING" etc opt usr
rm -rf "$STAGING"

sync_assets() {
  local ip="$1"
  local tgz
  tgz=$(remote_asset_path "$ip")
  echo "  assets -> $ip ($tgz)"
  if is_private_ip "$ip"; then
    "${SCP[@]}" /tmp/slurm-hybrid-assets.tgz "${CTRL1}:/tmp/slurm-hybrid-assets.tgz"
    run_ctrl1 "scp -i ${CLUSTER_KEY} -o StrictHostKeyChecking=no /tmp/slurm-hybrid-assets.tgz slurmadmin@${ip}:/tmp/"
    tgz="/tmp/slurm-hybrid-assets.tgz"
  else
    scp_to_host "$ip" /tmp/slurm-hybrid-assets.tgz "$tgz"
  fi
  # Never tar -C / — archive etc/ metadata overwrites /etc ownership and breaks munge.
  run_host "$ip" "sudo bash -s" <<REMOTE
set -euo pipefail
TGZ='${tgz//\'/\'\\\'\'}'
STAGING=\$(mktemp -d)
trap 'rm -rf "\$STAGING"' EXIT
tar xzf "\$TGZ" -C "\$STAGING"
install -d -m 755 /etc/slurm /opt/slurm-hybrid /usr/sbin
cp -r --no-preserve=ownership "\$STAGING/etc/slurm/." /etc/slurm/
cp -r --no-preserve=ownership "\$STAGING/opt/slurm-hybrid/." /opt/slurm-hybrid/
cp -r --no-preserve=ownership "\$STAGING/usr/sbin/." /usr/sbin/
chown root:root / /etc /usr /opt
chmod 755 / /etc /usr /opt
chown root:root /etc/slurm
chmod 755 /etc/slurm
chown root:root /etc/slurm/slurm.conf /etc/slurm/cgroup.conf 2>/dev/null || true
chmod 644 /etc/slurm/slurm.conf /etc/slurm/cgroup.conf 2>/dev/null || true
chown slurm:slurm /etc/slurm/slurmdbd.conf 2>/dev/null || true
chmod 600 /etc/slurm/slurmdbd.conf 2>/dev/null || true
REMOTE
  run_host "$ip" sudo chmod +x /opt/slurm-hybrid/install-slurm.sh /opt/slurm-hybrid/bootstrap-controller.sh /opt/slurm-hybrid/bootstrap-login.sh /opt/slurm-hybrid/bootstrap-compute.sh /usr/sbin/slurm_resume /usr/sbin/slurm_suspend /usr/sbin/slurm_resume_fail
  run_host "$ip" sudo rm -f "$tgz"
}

for ip in "$CTRL1_IP" "$CTRL2_IP" "$LOGIN_IP"; do
  if [[ "$ip" == "$LOGIN_IP" && "$LOGIN_REACHABLE" != true ]]; then
    echo "  skip assets -> login (unreachable)"
    continue
  fi
  sync_assets "$ip"
done

if [[ -n "${DB_PASSWORD:-}" ]]; then
  for ip in "$CTRL1_IP" "$CTRL2_IP"; do
    run_host "$ip" "sudo bash -s" <<REMOTE
install -d -m 755 /etc/slurm-hybrid
printf '%s\n' '${DB_PASSWORD//\'/\'\\\'\'}' | tee /etc/slurm-hybrid/db_password >/dev/null
chmod 600 /etc/slurm-hybrid/db_password
REMOTE
  done
fi

echo "==> Ensure slurmadmin keys on private nodes"
export SSH_KEY="$KEY" CTRL1_IP
PRIVATE_IPS="10.0.1.10 10.0.1.12 ${AWS_COMPUTE_IP}" bash "$(dirname "$0")/repair-slurmadmin-ssh.sh" || true

echo "==> Munge: install packages and sync key"
export SSH_KEY="$KEY" CTRL1_IP LOGIN_IP CTRL2_IP AWS_COMPUTE_IP GCP_COMPUTE_IP
bash "$(dirname "$0")/distribute-munge.sh"

echo "==> Build Slurm on ctrl1 (primary)"
run_ctrl1 "sudo bash -s" <<REMOTE
set -euo pipefail
export SLURM_VERSION=${SLURM_VERSION}
if [[ ! -x /opt/slurm-hybrid/install-slurm.sh ]]; then
  echo "install-slurm.sh missing — cloud-init incomplete" >&2
  exit 1
fi
if [[ ! -x /usr/local/sbin/slurmctld ]]; then
  bash /opt/slurm-hybrid/install-slurm.sh
fi
REMOTE

if [[ -n "${DB_PASSWORD:-}" ]]; then
  run_ctrl1 "sudo bash -s" <<REMOTE
set -e
export IS_PRIMARY=true
export SLURM_HOSTNAME=ctrl1
export DB_PASSWORD='${DB_PASSWORD//\'/\'\\\'\'}'
export SLURM_VERSION=${SLURM_VERSION}
export CLUSTER_NAME=${CLUSTER_NAME}
export AWS_COMPUTE_ID='${AWS_COMPUTE_INSTANCE_ID:-}'
export GCP_PROJECT=${GCP_PROJECT}
export GCP_ZONE=${GCP_ZONE}
export GCP_INSTANCE=${GCP_INSTANCE}
bash /opt/slurm-hybrid/bootstrap-controller.sh
REMOTE
fi

echo "==> Package Slurm binaries from ctrl1"
run_ctrl1 'sudo tar czf /tmp/slurm-hybrid-bin.tgz -C /usr/local bin sbin libexec lib 2>/dev/null; sudo tar czf /tmp/slurm-hybrid-units.tgz -C / etc/systemd/system/slurmd.service etc/systemd/system/slurmctld.service etc/systemd/system/slurmdbd.service 2>/dev/null; sudo chmod a+r /tmp/slurm-hybrid-*.tgz'

sync_slurm_binaries() {
  local ip="$1"
  echo "  sync binaries -> $ip"
  run_ctrl1 "scp -i ${CLUSTER_KEY} -o StrictHostKeyChecking=no /tmp/slurm-hybrid-bin.tgz slurmadmin@${ip}:/tmp/"
  run_host "$ip" 'sudo tar xzf /tmp/slurm-hybrid-bin.tgz -C /usr/local
    sudo ldconfig
    sudo tar xzf /tmp/slurm-hybrid-units.tgz -C / 2>/dev/null || true
    sudo systemctl daemon-reload'
}

for ip in 10.0.1.12 10.0.1.10; do sync_slurm_binaries "$ip"; done

echo "==> Bootstrap ctrl2"
run_host 10.0.1.12 "sudo bash -s" <<REMOTE
export IS_PRIMARY=false
export SLURM_HOSTNAME=ctrl2
export SLURM_VERSION=${SLURM_VERSION}
bash /opt/slurm-hybrid/bootstrap-controller.sh 2>/dev/null || {
  sudo systemctl enable munge slurmctld
  sudo systemctl restart munge slurmctld
}
REMOTE

echo "==> Bootstrap login (client)"
if [[ "$LOGIN_REACHABLE" == true ]]; then
  run_host "${LOGIN_IP}" "sudo bash -s" <<REMOTE
export SLURM_VERSION=${SLURM_VERSION}
bash /opt/slurm-hybrid/bootstrap-login.sh 2>/dev/null || true
sudo systemctl enable munge
sudo systemctl restart munge
REMOTE
else
  echo "WARN: login bootstrap skipped — re-run workflow after login instance is replaced"
fi

echo "==> Deploy compute nodes (offline bundle from ctrl1)"
export SSH_KEY="$KEY" GCP_PROJECT GCP_ZONE GCP_INSTANCE CLUSTER_NAME
if command -v aws >/dev/null 2>&1; then
  echo "==> Hybrid VPN status"
  aws ec2 describe-vpn-connections \
    --filters "Name=tag:Name,Values=${CLUSTER_NAME}-vpn-gcp" \
    --query 'VpnConnections[0].VgwTelemetry[0].Status' --output text 2>/dev/null \
    | xargs -I{} echo "  AWS tunnel: {}" || true
fi
bash "$(dirname "$0")/deploy-compute-node.sh" aws "${AWS_COMPUTE_IP}"
bash "$(dirname "$0")/deploy-compute-node.sh" gcp

if [[ -n "${GCP_SA_KEY_FILE:-}" && -f "${GCP_SA_KEY_FILE}" ]]; then
  echo "==> GCP power-save key on controllers"
  for t in "$CTRL1" "$CTRL2"; do
    "${SCP[@]}" "${GCP_SA_KEY_FILE}" "${t}:/tmp/gcp-sa.json"
    "${SSH[@]}" "$t" 'sudo mv /tmp/gcp-sa.json /etc/slurm/gcp-sa.json && sudo chmod 600 /etc/slurm/gcp-sa.json
      gcloud auth activate-service-account --key-file=/etc/slurm/gcp-sa.json 2>/dev/null || true'
  done
fi

echo "==> Verify cluster"
run_ctrl1 'sudo systemctl is-active munge mariadb slurmdbd slurmctld 2>/dev/null; sinfo 2>/dev/null || /usr/local/bin/sinfo 2>/dev/null || echo sinfo-pending'

echo "Bootstrap complete."
