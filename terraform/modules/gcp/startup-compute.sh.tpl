#!/bin/bash
set -euo pipefail

mkdir -p /etc/slurm /opt/slurm-hybrid
cat > /etc/slurm/slurm.conf <<'SLURM_EOF'
${slurm_conf}
SLURM_EOF

cat > /opt/slurm-hybrid/install-slurm.sh <<'INSTALL_EOF'
${install_script}
INSTALL_EOF
chmod +x /opt/slurm-hybrid/install-slurm.sh

cat > /opt/slurm-hybrid/bootstrap-compute.sh <<'BOOT_EOF'
${bootstrap_compute}
BOOT_EOF
chmod +x /opt/slurm-hybrid/bootstrap-compute.sh

export SLURM_VERSION="${slurm_version}"
export NODE_NAME="${node_name}"
export CLOUD_PROVIDER="${cloud_provider}"
export INSTANCE_ID="${instance_name}"

/opt/slurm-hybrid/bootstrap-compute.sh
