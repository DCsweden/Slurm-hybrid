#!/bin/bash
# Repair slurmadmin SSH and filesystem permissions on EC2 nodes where cloud-init failed
# or / was incorrectly chmodded (blocks all non-ubuntu users from executing anything).
set -euo pipefail

KEY="${SSH_KEY:-${HOME}/.ssh/cluster_key}"
KEY="${KEY/#\~/$HOME}"
IP="${1:?usage: fix-node-access.sh <public-ip>}"
PUB="${SSH_PUBLIC_KEY:-}"

if [[ -z "$PUB" ]]; then
  PUB=$(ssh-keygen -y -f "$KEY")
fi

SSH=(ssh -i "$KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=30)

echo "==> Fix node access: $IP (via ubuntu)"
"${SSH[@]}" "ubuntu@${IP}" "bash -s" <<REMOTE
set -euo pipefail
PUB='${PUB//\'/\'\\\'\'}'
H=\$(hostname)

run_root() {
  if sudo -n "\$@" 2>/dev/null; then
    return 0
  fi
  if [[ "\$(id -u)" -eq 0 ]]; then
    "\$@"
    return \$?
  fi
  echo "ERROR: need root (sudo broken — replace this EC2 instance)" >&2
  return 1
}

# Phase 1: fix / without sudo when ubuntu owns it (tarball corruption)
if [[ "\$(stat -c '%U' /)" == "ubuntu" ]]; then
  chmod 755 / || true
fi

# Phase 2: restore sudo if setuid was stripped
if [[ -f /usr/bin/sudo ]] && [[ "\$(stat -c '%a' /usr/bin/sudo)" != "4755" ]]; then
  run_root chmod 4755 /usr/bin/sudo
fi
if ! sudo -n true 2>/dev/null; then
  echo "ERROR: sudo still broken on \${H} — run: terraform apply -replace=module.aws.aws_instance.login" >&2
  exit 1
fi

run_root chmod 755 /
run_root chown root:root /
ROOT_PERM=\$(stat -c '%a' /)
ROOT_OWNER=\$(stat -c '%U:%G' /)
if [[ "\$ROOT_PERM" != "755" || "\$ROOT_OWNER" != "root:root" ]]; then
  echo "ERROR: could not fix / (\$ROOT_PERM \$ROOT_OWNER)" >&2
  exit 1
fi

run_root bash -c 'grep -q "\${H}" /etc/hosts || echo "127.0.1.1 \${H}" >> /etc/hosts'

if ! id slurmadmin &>/dev/null; then
  run_root useradd -m -s /bin/bash -G sudo slurmadmin
  echo 'slurmadmin ALL=(ALL) NOPASSWD:ALL' | run_root tee /etc/sudoers.d/90-slurmadmin >/dev/null
  run_root chmod 440 /etc/sudoers.d/90-slurmadmin
fi
run_root passwd -d slurmadmin >/dev/null 2>&1 || true

run_root install -d -m 700 -o slurmadmin -g slurmadmin /home/slurmadmin/.ssh
AUTH=/home/slurmadmin/.ssh/authorized_keys
run_root touch "\$AUTH"
run_root bash -c 'grep -qxF "\$PUB" "\$AUTH" 2>/dev/null || echo "\$PUB" >> "\$AUTH"'
if [[ -f /home/ubuntu/.ssh/authorized_keys ]]; then
  while read -r line; do
    [[ -n "\$line" ]] && ! sudo grep -qxF "\$line" "\$AUTH" 2>/dev/null && echo "\$line" | sudo tee -a "\$AUTH" >/dev/null
  done < /home/ubuntu/.ssh/authorized_keys
fi
run_root chown -R slurmadmin:slurmadmin /home/slurmadmin/.ssh
run_root chmod 600 "\$AUTH"

for f in /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf; do
  [[ -f "\$f" ]] || continue
  if sudo grep -q '^AllowUsers' "\$f" && ! sudo grep -q 'slurmadmin' "\$f"; then
    sudo sed -i 's/^AllowUsers\(.*\)$/AllowUsers\1 slurmadmin/' "\$f"
  fi
done
sudo systemctl reload ssh 2>/dev/null || sudo systemctl reload sshd 2>/dev/null || true

if ! sudo runuser -u slurmadmin -- true 2>/dev/null; then
  echo "ERROR: slurmadmin cannot execute (check / permissions: \$(stat -c '%a %U:%G' /))" >&2
  exit 1
fi
echo "slurmadmin account OK on \${H}"
REMOTE

if "${SSH[@]}" "slurmadmin@${IP}" 'echo ready' 2>/dev/null; then
  echo "  slurmadmin@${IP} OK"
else
  echo "ERROR: slurmadmin@${IP} still unreachable after repair" >&2
  exit 1
fi
