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
"${SSH[@]}" "ubuntu@${IP}" "sudo bash -s" <<REMOTE
set -euo pipefail
PUB='${PUB//\'/\'\\\'\'}'
H=\$(hostname)

# Broken / (700 ubuntu) prevents slurmadmin from running any binary — fix first.
ROOT_PERM=\$(stat -c '%a' /)
ROOT_OWNER=\$(stat -c '%U:%G' /)
if [[ "\$ROOT_PERM" != "755" || "\$ROOT_OWNER" != "root:root" ]]; then
  echo "WARN: fixing / (\$ROOT_PERM \$ROOT_OWNER -> 755 root:root)"
  chmod 755 /
  chown root:root /
fi
USR_OWNER=\$(stat -c '%U:%G' /usr 2>/dev/null || echo unknown)
if [[ "\$USR_OWNER" != "root:root" ]]; then
  echo "WARN: fixing /usr owner (\$USR_OWNER -> root:root)"
  chown -R root:root /usr
fi

grep -q "\${H}" /etc/hosts || echo "127.0.1.1 \${H}" >> /etc/hosts

if ! id slurmadmin &>/dev/null; then
  useradd -m -s /bin/bash -G sudo slurmadmin
  echo 'slurmadmin ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-slurmadmin
  chmod 440 /etc/sudoers.d/90-slurmadmin
fi
passwd -d slurmadmin >/dev/null 2>&1 || true

install -d -m 700 -o slurmadmin -g slurmadmin /home/slurmadmin/.ssh
AUTH=/home/slurmadmin/.ssh/authorized_keys
touch "\$AUTH"
grep -qxF "\$PUB" "\$AUTH" 2>/dev/null || echo "\$PUB" >> "\$AUTH"
if [[ -f /home/ubuntu/.ssh/authorized_keys ]]; then
  while read -r line; do
    [[ -n "\$line" ]] && ! grep -qxF "\$line" "\$AUTH" 2>/dev/null && echo "\$line" >> "\$AUTH"
  done < /home/ubuntu/.ssh/authorized_keys
fi
chown -R slurmadmin:slurmadmin /home/slurmadmin/.ssh
chmod 600 "\$AUTH"

for f in /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf; do
  [[ -f "\$f" ]] || continue
  if grep -q '^AllowUsers' "\$f" && ! grep -q 'slurmadmin' "\$f"; then
    sed -i 's/^AllowUsers\(.*\)$/AllowUsers\1 slurmadmin/' "\$f"
  fi
done
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true

if ! runuser -u slurmadmin -- true 2>/dev/null; then
  echo "ERROR: slurmadmin still cannot execute after repair" >&2
  stat -c '%a %U:%G' /
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
