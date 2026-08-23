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

# Install Vagrant insecure public keys. The upstream file is fetched from the
# "main" branch (floating ref, #30 공급망 고정), so it is only trusted when its
# content matches one of the known-good embedded keys above; a fetch that
# succeeds but returns something unexpected (compromised branch, MITM,
# unexpected upstream edit) falls back to the embedded keys instead of being
# trusted blindly.
echo "Installing Vagrant insecure public keys..."
FETCHED_KEYS=""
if FETCHED_KEYS=$(curl -fsSL --connect-timeout 10 https://raw.githubusercontent.com/hashicorp/vagrant/main/keys/vagrant.pub 2>/dev/null); then # unpinned-guard:allow -- content verified against embedded keys below, not trusted blindly
  if printf '%s\n' "$FETCHED_KEYS" | grep -qF "$VAGRANT_INSECURE_KEY_RSA" && printf '%s\n' "$FETCHED_KEYS" | grep -qF "$VAGRANT_INSECURE_KEY_ED25519"; then
    printf '%s\n' "$FETCHED_KEYS" > "${SSH_DIR}/authorized_keys"
    echo "Downloaded keys from GitHub (matched known-good embedded keys)"
  else
    echo "Downloaded key content did NOT match known-good embedded keys; using embedded keys instead"
    echo "${VAGRANT_INSECURE_KEY_RSA}" > "${SSH_DIR}/authorized_keys"
    echo "${VAGRANT_INSECURE_KEY_ED25519}" >> "${SSH_DIR}/authorized_keys"
  fi
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
