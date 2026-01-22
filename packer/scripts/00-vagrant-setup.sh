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

# Create .ssh directory
echo "Creating .ssh directory..."
mkdir -p "${SSH_DIR}"

# Download and install Vagrant insecure public key
echo "Installing Vagrant insecure public key..."
curl -fsSL https://raw.githubusercontent.com/hashicorp/vagrant/main/keys/vagrant.pub \
  -o "${SSH_DIR}/authorized_keys"

# Set proper permissions
echo "Setting permissions..."
chmod 700 "${SSH_DIR}"
chmod 600 "${SSH_DIR}/authorized_keys"
chown -R "${VAGRANT_USER}:${VAGRANT_USER}" "${SSH_DIR}"

# Verify
echo "Verifying SSH key installation..."
ls -la "${SSH_DIR}"
cat "${SSH_DIR}/authorized_keys"

echo "=== 00-vagrant-setup.sh: Complete ==="
