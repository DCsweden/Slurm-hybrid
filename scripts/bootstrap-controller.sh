#!/bin/bash
set -euo pipefail

source /tmp/bootstrap-vars.env 2>/dev/null || true

SLURM_HOSTNAME="${SLURM_HOSTNAME:-ctrl1}"
if [[ "$(hostname -s)" != "$SLURM_HOSTNAME" ]]; then
  hostnamectl set-hostname "$SLURM_HOSTNAME"
  grep -q "$SLURM_HOSTNAME" /etc/hosts || echo "127.0.1.1 $SLURM_HOSTNAME" >> /etc/hosts
fi

/opt/slurm-hybrid/install-slurm.sh

# Munge key (primary generates; backup copies from ctrl1 manually or shared secret)
if [[ "${IS_PRIMARY:-false}" == "true" ]]; then
  if [[ ! -f /etc/munge/munge.key ]]; then
    create-munge-key
    chown munge:munge /etc/munge/munge.key
    chmod 400 /etc/munge/munge.key
  fi
  systemctl enable --now munge

  if [[ -f /etc/slurm-hybrid/db_password ]]; then
    DB_PASSWORD=$(cat /etc/slurm-hybrid/db_password)
  fi
  sed -i "s/SLURM_DB_PASSWORD/${DB_PASSWORD}/" /etc/slurm/slurmdbd.conf
  chmod 600 /etc/slurm/slurmdbd.conf
  chown slurm:slurm /etc/slurm/slurmdbd.conf
  mysql -e "CREATE DATABASE IF NOT EXISTS slurm_acct_db;"
  mysql -e "CREATE USER IF NOT EXISTS 'slurm'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';"
  mysql -e "GRANT ALL ON slurm_acct_db.* TO 'slurm'@'localhost';"
  mysql -e "FLUSH PRIVILEGES;"

  systemctl enable --now slurmdbd
  for i in $(seq 1 30); do
    ss -tln 2>/dev/null | grep -q ':6819 ' && break
    sleep 2
  done

  sacctmgr -i create cluster name="${CLUSTER_NAME:-slurm-hybrid}" 2>/dev/null || true

  # cloud-nodes.json with live instance IDs from Terraform env
  if [[ -n "${AWS_COMPUTE_ID:-}" ]]; then
    jq -n \
      --arg aws_id "$AWS_COMPUTE_ID" \
      --arg gcp_inst "${GCP_INSTANCE:-gcp-compute}" \
      --arg gcp_zone "${GCP_ZONE:-}" \
      '{
        "aws-compute": {"provider":"aws","instance_id":$aws_id,"zone":""},
        "gcp-compute": {"provider":"gcp","instance_id":$gcp_inst,"zone":$gcp_zone}
      }' > /etc/slurm/cloud-nodes.json
  fi

  systemctl enable --now slurmctld
else
  systemctl enable --now munge
  systemctl enable --now slurmctld
fi

# GCP credentials for power save (place SA JSON at /etc/slurm/gcp-sa.json)
if [[ -f /etc/slurm/gcp-sa.json ]]; then
  gcloud auth activate-service-account --key-file=/etc/slurm/gcp-sa.json
fi

echo "Controller bootstrap done (primary=${IS_PRIMARY:-false})"
