#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail

install -d -m 0755 /usr/local/sbin /etc/systemd/system
install -m 0755 /usr/local/sbin/kube-ready-first-boot <<'SCRIPT'
#!/bin/bash
set -euo pipefail

# Generate a unique machine identity after cloning a released image.
if [ ! -s /etc/machine-id ]; then
  systemd-machine-id-setup
fi
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id 2>/dev/null || true

# Ensure SSH host keys are generated from the unique node identity.
ssh-keygen -A

# Optional hardened profile: disable the Vagrant insecure trust after the first
# successful boot. Operators must provision an explicit production key before
# enabling this profile.
if [ -f /etc/kube-ready/hardened-ssh ]; then
  rm -f /home/vagrant/.ssh/authorized_keys
  install -d -m 0700 /home/vagrant/.ssh
  chown -R vagrant:vagrant /home/vagrant/.ssh
fi

# Record a non-secret identity attestation.
install -d -m 0755 /etc/vagrant-box
printf '{"schema":"kube-ready-identity/v1","machine_id":"%s","ssh_host_keys_generated":true,"hardened_ssh":%s}\n' \
  "$(cat /etc/machine-id)" \
  "$([ -f /etc/kube-ready/hardened-ssh ] && echo true || echo false)" \
  > /etc/vagrant-box/identity-attestation.json

systemctl disable kube-ready-first-boot.service >/dev/null 2>&1 || true
rm -f /etc/systemd/system/kube-ready-first-boot.service
systemctl daemon-reload
SCRIPT

cat > /etc/systemd/system/kube-ready-first-boot.service <<'UNIT'
[Unit]
Description=kube-ready-box first boot identity initialization
ConditionPathExists=/usr/local/sbin/kube-ready-first-boot
After=systemd-machine-id-commit.service ssh.service network-pre.target
Before=sshd.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/kube-ready-first-boot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT

systemctl enable kube-ready-first-boot.service
