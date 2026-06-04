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
LOGIN_SSH_USER=slurmadmin
LOGIN_SSH_IP=""

try_ssh_ip() {
  local ip="$1"
  local track_login="${2:-false}"
  for user in slurmadmin ubuntu; do
    if "${SSH[@]}" "${user}@${ip}" 'echo ready' 2>/dev/null; then
      if [[ "$track_login" == true ]]; then
        LOGIN_SSH_USER="$user"
        LOGIN_SSH_IP="$ip"
        LOGIN_REACHABLE=true
      fi
      return 0
    fi
  done
  return 1
}

wait_ssh() {
  local ip="$1"
  local label="${2:-slurmadmin@${ip}}"
  echo "Waiting for SSH: $label"
  for i in $(seq 1 60); do
    if try_ssh_ip "$ip" false; then
      echo "  ready (slurmadmin@${ip})"
      return 0
    fi
    if (( i % 6 == 0 )); then echo "  still waiting (${i}/60)..."; fi
    sleep 10
  done
  echo "Timeout waiting for $label" >&2
  exit 1
}

wait_ssh_optional() {
  local ip="$1"
  local label="${2:-slurmadmin@${ip}}"
  echo "Waiting for SSH (optional): $label"
  for i in $(seq 1 18); do
    if try_ssh_ip "$ip" true; then
      echo "  ready (${LOGIN_SSH_USER}@${LOGIN_SSH_IP})"
      return 0
    fi
    if (( i % 3 == 0 )); then echo "  still waiting (${i}/18)..."; fi
    sleep 10
  done
  echo "WARN: login not reachable yet — continuing (retry after ctrl1 setup)"
  return 0
}

run_login() {
  if [[ "$LOGIN_REACHABLE" != true ]]; then
    echo "SKIP login: not reachable" >&2
    return 0
  fi
  "${SSH[@]}" "${LOGIN_SSH_USER}@${LOGIN_IP}" "$@"
}

scp_to_host() {
  local ip="$1"
  local src="$2"
  local dest="$3"
  local user=slurmadmin
  if [[ "$ip" == "$LOGIN_IP" && "$LOGIN_REACHABLE" == true ]]; then
    user="$LOGIN_SSH_USER"
  fi
  "${SCP[@]}" "$src" "${user}@${ip}:${dest}"
}

ensure_login_slurmadmin() {
  [[ "$LOGIN_REACHABLE" == true ]] || return 0
  if "${SSH[@]}" "slurmadmin@${LOGIN_IP}" 'echo ok' 2>/dev/null; then
    LOGIN_SSH_USER=slurmadmin
    return 0
  fi
  echo "==> Install slurmadmin SSH key on login (via ${LOGIN_SSH_USER})"
  local pub
  pub=$(ssh-keygen -y -f "$KEY")
  run_login "sudo bash -s" <<REMOTE
set -e
install -d -m 700 -o slurmadmin -g slurmadmin /home/slurmadmin/.ssh
AUTH=/home/slurmadmin/.ssh/authorized_keys
touch "\$AUTH"
grep -qxF '${pub//\'/\'\\\'\'}' "\$AUTH" 2>/dev/null || echo '${pub//\'/\'\\\'\'}' >> "\$AUTH"
chown slurmadmin:slurmadmin "\$AUTH"
chmod 600 "\$AUTH"
REMOTE
  if "${SSH[@]}" "slurmadmin@${LOGIN_IP}" 'echo ok' 2>/dev/null; then
    LOGIN_SSH_USER=slurmadmin
    echo "  slurmadmin SSH on login OK"
  else
    echo "WARN: slurmadmin still unavailable on login — using ${LOGIN_SSH_USER}" >&2
  fi
}

echo "==> Wait for controllers"
wait_ssh "$CTRL1_IP" "$CTRL1"
wait_ssh "$CTRL2_IP" "$CTRL2"

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
wait_ssh_optional "$LOGIN_IP" "$LOGIN"
if [[ "$LOGIN_REACHABLE" != true ]]; then
  try_ssh_ip "10.0.1.10" true && echo "  login reachable via private 10.0.1.10"
fi
ensure_login_slurmadmin

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
tar czf /tmp/slurm-hybrid-assets.tgz -C "$STAGING" .
rm -rf "$STAGING"

sync_assets() {
  local ip="$1"
  echo "  assets -> $ip"
  if is_private_ip "$ip"; then
    "${SCP[@]}" /tmp/slurm-hybrid-assets.tgz "${CTRL1}:/tmp/slurm-hybrid-assets.tgz"
    run_ctrl1 "scp -i ${CLUSTER_KEY} -o StrictHostKeyChecking=no /tmp/slurm-hybrid-assets.tgz slurmadmin@${ip}:/tmp/"
  else
    scp_to_host "$ip" /tmp/slurm-hybrid-assets.tgz /tmp/
  fi
  run_host "$ip" sudo tar xzf /tmp/slurm-hybrid-assets.tgz -C /
  run_host "$ip" sudo chmod +x /opt/slurm-hybrid/install-slurm.sh /opt/slurm-hybrid/bootstrap-controller.sh /opt/slurm-hybrid/bootstrap-login.sh /opt/slurm-hybrid/bootstrap-compute.sh /usr/sbin/slurm_resume /usr/sbin/slurm_suspend /usr/sbin/slurm_resume_fail
  run_host "$ip" sudo rm -f /tmp/slurm-hybrid-assets.tgz
}

for ip in "$LOGIN_IP" "$CTRL1_IP" "$CTRL2_IP" "$AWS_COMPUTE_IP"; do
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
run_ctrl1 'sudo tar czf /tmp/slurm-hybrid-bin.tgz -C /usr/local bin sbin libexec lib 2>/dev/null; sudo tar czf /tmp/slurm-hybrid-units.tgz etc/systemd/system/slurmd.service etc/systemd/system/slurmctld.service 2>/dev/null; sudo chmod a+r /tmp/slurm-hybrid-*.tgz'

sync_slurm_binaries() {
  local ip="$1"
  echo "  sync binaries -> $ip"
  run_ctrl1 "scp -i ${CLUSTER_KEY} -o StrictHostKeyChecking=no /tmp/slurm-hybrid-bin.tgz slurmadmin@${ip}:/tmp/"
  run_host "$ip" 'sudo tar xzf /tmp/slurm-hybrid-bin.tgz -C /usr/local
    sudo ldconfig
    sudo tar xzf /tmp/slurm-hybrid-units.tgz -C / 2>/dev/null || true
    sudo systemctl daemon-reload'
}

for ip in 10.0.1.12 10.0.1.10 10.0.2.10; do sync_slurm_binaries "$ip"; done

echo "==> Bootstrap ctrl2"
run_host 10.0.1.12 "sudo bash -s" <<REMOTE
export IS_PRIMARY=false
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

echo "==> Bootstrap aws-compute"
INSTANCE_ID="${AWS_COMPUTE_INSTANCE_ID:-}"
run_host 10.0.2.10 "sudo bash -s" <<REMOTE
export SLURM_VERSION=${SLURM_VERSION}
export NODE_NAME=aws-compute
export CLOUD_PROVIDER=aws
export INSTANCE_ID=${INSTANCE_ID}
bash /opt/slurm-hybrid/bootstrap-compute.sh
REMOTE

echo "==> GCP: munge debs + slurm tarball + slurmd"
# Download munge debs on runner from ctrl1
mkdir -p /tmp/slurm-bootstrap
"${SCP[@]}" "${CTRL1}:/tmp/libmunge2_0.5.14-6ubuntu0.1_amd64.deb" /tmp/slurm-bootstrap/ 2>/dev/null || \
  run_ctrl1 'apt-get download -o Dir::Cache::archives=/tmp libmunge2 munge 2>/dev/null; ls /tmp/*.deb' || true
run_ctrl1 'cd /tmp && apt-get download libmunge2 munge 2>/dev/null || true'
"${SCP[@]}" "${CTRL1}:/tmp/libmunge2"*.deb "${CTRL1}:/tmp/munge"*.deb /tmp/slurm-bootstrap/ 2>/dev/null || true
"${SCP[@]}" "${CTRL1}:/tmp/slurm-hybrid-bin.tgz" /tmp/slurm-bootstrap/

MKEY_B64=$(run_ctrl1 'sudo cat /etc/munge/munge.key | base64 -w0')

gcloud compute scp --project="${GCP_PROJECT}" --zone="${GCP_ZONE}" --tunnel-through-iap \
  /tmp/slurm-bootstrap/libmunge2*.deb /tmp/slurm-bootstrap/munge*.deb \
  /tmp/slurm-bootstrap/slurm-hybrid-bin.tgz \
  "${GCP_INSTANCE}:/tmp/" 2>/dev/null || true

gcloud compute ssh "${GCP_INSTANCE}" --project="${GCP_PROJECT}" --zone="${GCP_ZONE}" --tunnel-through-iap --command="
set -e
sudo dpkg -i /tmp/libmunge2*.deb /tmp/munge*.deb 2>/dev/null || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y munge
echo '${MKEY_B64}' | base64 -d | sudo tee /etc/munge/munge.key >/dev/null
sudo chown munge:munge /etc/munge/munge.key && sudo chmod 400 /etc/munge/munge.key
sudo systemctl enable --now munge
sudo tar xzf /tmp/slurm-hybrid-bin.tgz -C /usr/local && sudo ldconfig
export SLURM_VERSION=${SLURM_VERSION} NODE_NAME=gcp-compute CLOUD_PROVIDER=gcp INSTANCE_ID=${GCP_INSTANCE}
bash /opt/slurm-hybrid/bootstrap-compute.sh 2>/dev/null || sudo systemctl enable --now slurmd
sudo systemctl is-active munge slurmd
"

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
