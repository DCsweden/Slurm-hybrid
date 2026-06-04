#!/bin/bash
# Build Slurm from source on Ubuntu 22.04 (SchedMD releases)
set -euo pipefail

SLURM_VERSION="${SLURM_VERSION:-24.05.3}"
PREFIX=/usr/local

SUDO=""
[[ "$(id -u)" -ne 0 ]] && SUDO="sudo"

$SUDO apt-get update
DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y \
  build-essential fakeroot devscripts equivs \
  libmunge-dev libmariadb-dev libpam0g-dev libhwloc-dev \
  libjson-c-dev libhttp-parser-dev libyaml-dev \
  liblua5.3-dev libdbus-1-dev libssl-dev \
  munge mariadb-server jq awscli python3-pip

# Google Cloud SDK (for Resume/Suspend on GCP from controllers)
if ! command -v gcloud >/dev/null 2>&1; then
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    > /etc/apt/sources.list.d/google-cloud-sdk.list
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
  $SUDO apt-get update && $SUDO apt-get install -y google-cloud-cli
fi

id -u slurm &>/dev/null || $SUDO useradd -r -s /sbin/nologin slurm
id -u slurmadmin &>/dev/null || $SUDO useradd -m -s /bin/bash slurmadmin

cd /tmp
curl -fsSLO "https://download.schedmd.com/slurm/slurm-${SLURM_VERSION}.tar.bz2"
tar xf "slurm-${SLURM_VERSION}.tar.bz2"
cd "slurm-${SLURM_VERSION}"

./configure --prefix="$PREFIX" --sysconfdir=/etc/slurm --enable-pam --with-mysql
make -j"$(nproc)"
$SUDO make install
$SUDO ldconfig

$SUDO mkdir -p /etc/slurm /var/spool/slurmctld /var/log/slurm
$SUDO chown slurm:slurm /var/spool/slurmctld

$SUDO cp -f etc/cgroup.conf.example /etc/slurm/cgroup.conf 2>/dev/null || true

$SUDO tee /etc/systemd/system/slurmctld.service >/dev/null <<'UNIT'
[Unit]
Description=Slurm controller daemon
After=munge.service mariadb.service network-online.target
Wants=network-online.target

[Service]
Type=forking
EnvironmentFile=-/etc/default/slurmctld
ExecStart=/usr/local/sbin/slurmctld -f /etc/slurm/slurm.conf
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/var/run/slurmctld.pid
User=slurm

[Install]
WantedBy=multi-user.target
UNIT

$SUDO tee /etc/systemd/system/slurmdbd.service >/dev/null <<'UNIT'
[Unit]
Description=Slurm DBD
After=munge.service mariadb.service

[Service]
ExecStart=/usr/local/sbin/slurmdbd -f /etc/slurm/slurmdbd.conf
User=slurm

[Install]
WantedBy=multi-user.target
UNIT

$SUDO tee /etc/systemd/system/slurmd.service >/dev/null <<'UNIT'
[Unit]
Description=Slurm node daemon
After=munge.service network-online.target

[Service]
ExecStart=/usr/local/sbin/slurmd -f /etc/slurm/slurm.conf
User=root

[Install]
WantedBy=multi-user.target
UNIT

$SUDO systemctl daemon-reload
