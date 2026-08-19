#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail

install -d -m 0755 /usr/local/sbin /etc/systemd/system /etc/kube-ready
cat > /usr/local/sbin/kube-ready-first-boot <<'SCRIPT'
#!/bin/bash
set -euo pipefail

if [ ! -s /etc/machine-id ]; then
  systemd-machine-id-setup
fi
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id 2>/dev/null || true

ssh-keygen -A

if [ -f /etc/kube-ready/hardened-ssh ]; then
  rm -f /home/vagrant/.ssh/authorized_keys
  install -d -m 0700 /home/vagrant/.ssh
  chown -R vagrant:vagrant /home/vagrant/.ssh
fi

install -d -m 0755 /etc/vagrant-box
python3 - <<'PY'
import json
from pathlib import Path
Path('/etc/vagrant-box/identity-attestation.json').write_text(json.dumps({
  'schema':'kube-ready-identity/v1',
  'machine_id':Path('/etc/machine-id').read_text().strip(),
  'ssh_host_keys_generated':True,
  'hardened_ssh':Path('/etc/kube-ready/hardened-ssh').exists()
}, sort_keys=True, separators=(',',':'))+'\n')
PY

systemctl disable kube-ready-first-boot.service >/dev/null 2>&1 || true
rm -f /etc/systemd/system/kube-ready-first-boot.service
systemctl daemon-reload
SCRIPT
chmod 0755 /usr/local/sbin/kube-ready-first-boot

cat > /etc/systemd/system/kube-ready-first-boot.service <<'UNIT'
[Unit]
Description=kube-ready-box first boot identity initialization
ConditionPathExists=/usr/local/sbin/kube-ready-first-boot
After=local-fs.target
Before=ssh.service sshd.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/kube-ready-first-boot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT

systemctl enable kube-ready-first-boot.service
