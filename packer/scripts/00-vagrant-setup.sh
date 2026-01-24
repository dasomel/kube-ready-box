#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 dasomel
#
# Setup Vagrant insecure keypair for SSH authentication
set -e

echo "=== 00-vagrant-setup.sh: Vagrant SSH Key Setup ==="

VAGRANT_USER="vagrant"
VAGRANT_HOME="/home/${VAGRANT_USER}"
SSH_DIR="${VAGRANT_HOME}/.ssh"

# Vagrant insecure public keys (fallback if curl fails)
VAGRANT_INSECURE_KEY_RSA="ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key"
VAGRANT_INSECURE_KEY_ED25519="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN1YdxBpNlzxDqfJyw/QKow1F+wvG9hXGoqiysfJOn5Y vagrant insecure public key"

# Create .ssh directory
echo "Creating .ssh directory..."
mkdir -p "${SSH_DIR}"

# Install Vagrant insecure public keys
echo "Installing Vagrant insecure public keys..."
if curl -fsSL --connect-timeout 10 https://raw.githubusercontent.com/hashicorp/vagrant/main/keys/vagrant.pub -o "${SSH_DIR}/authorized_keys" 2>/dev/null; then
  echo "Downloaded keys from GitHub"
else
  echo "Curl failed, using embedded keys..."
  echo "${VAGRANT_INSECURE_KEY_RSA}" > "${SSH_DIR}/authorized_keys"
  echo "${VAGRANT_INSECURE_KEY_ED25519}" >> "${SSH_DIR}/authorized_keys"
fi

# Verify keys were installed
if [ ! -s "${SSH_DIR}/authorized_keys" ]; then
  echo "Warning: authorized_keys is empty, adding embedded keys..."
  echo "${VAGRANT_INSECURE_KEY_RSA}" > "${SSH_DIR}/authorized_keys"
  echo "${VAGRANT_INSECURE_KEY_ED25519}" >> "${SSH_DIR}/authorized_keys"
fi

# Set proper permissions
echo "Setting permissions..."
chmod 700 "${SSH_DIR}"
chmod 600 "${SSH_DIR}/authorized_keys"
chown -R "${VAGRANT_USER}:${VAGRANT_USER}" "${SSH_DIR}"

# Verify
echo "Verifying SSH key installation..."
ls -la "${SSH_DIR}"
echo "authorized_keys content:"
cat "${SSH_DIR}/authorized_keys"
echo ""
echo "Key count: $(wc -l < "${SSH_DIR}/authorized_keys")"

echo "=== 00-vagrant-setup.sh: Complete ==="
