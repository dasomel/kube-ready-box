#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 dasomel
set -e

echo "=== Final Cleanup for Kube-ready Box ==="

apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*

find /var/log -type f -name "*.log" -exec truncate -s 0 {} \;
find /var/log -type f -name "*.gz" -delete
find /var/log -type f -name "*.1" -delete

unset HISTFILE
rm -f /root/.bash_history
rm -f /home/*/.bash_history

# Host keys are generated uniquely by the first-boot identity service.
echo "Removing SSH host keys from the image; first boot regenerates them..."
rm -f /etc/ssh/ssh_host_*

# A released image must not carry a source machine identity.
echo "Clearing machine identity..."
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id

# Remove transient identity evidence generated during the build.
rm -f /etc/vagrant-box/identity-attestation.json

# Optional production/hardened profile marker. Vagrant development images keep
# their insecure public key for Vagrant transport; production promotion should
# create /etc/kube-ready/hardened-ssh and provision an explicit operator key.
if [ "${KUBE_READY_HARDENED_SSH:-0}" = "1" ]; then
  mkdir -p /etc/kube-ready
  touch /etc/kube-ready/hardened-ssh
  rm -f /home/vagrant/.ssh/authorized_keys
fi

dd if=/dev/zero of=/EMPTY bs=1M 2>/dev/null || true
rm -f /EMPTY
sync

echo "=== Cleanup Complete ==="
