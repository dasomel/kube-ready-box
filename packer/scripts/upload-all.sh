#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 dasomel
#
# LEGACY: This script is superseded by the root upload-boxes.sh which supports
# version-parameterized builds (--version flag, UBUNTU_VERSION env var),
# multi-filesystem upload, and HCP auth. Use upload-boxes.sh for all new work.
#
set -e

#=========================================
# Vagrant Cloud Upload Script (legacy)
#=========================================

USERNAME="dasomel"
UBUNTU_VERSION="${UBUNTU_VERSION:-24.04}"
BOX_NAME="ubuntu-${UBUNTU_VERSION}"
VERSION="${1:-0.1.0}"

if [ -z "$1" ]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 0.1.0"
  exit 1
fi

# Check if boxes exist
for box in "${BOX_NAME}-virtualbox-amd64.box" \
           "${BOX_NAME}-virtualbox-arm64.box" \
           "${BOX_NAME}-vmware-amd64.box" \
           "${BOX_NAME}-vmware-arm64.box"; do
  if [ ! -f "../$box" ]; then
    echo "Error: Box file not found: $box"
    echo "Please run './build.sh all' first"
    exit 1
  fi
done

echo "=========================================="
echo "Uploading dasomel/${BOX_NAME} v${VERSION}"
echo "=========================================="

BOXES=(
  "virtualbox:amd64:${BOX_NAME}-virtualbox-amd64.box"
  "virtualbox:arm64:${BOX_NAME}-virtualbox-arm64.box"
  "vmware_desktop:amd64:${BOX_NAME}-vmware-amd64.box"
  "vmware_desktop:arm64:${BOX_NAME}-vmware-arm64.box"
)

for box in "${BOXES[@]}"; do
  IFS=':' read -r provider arch file <<< "$box"

  echo ""
  echo "Uploading: $file"
  echo "  Provider: $provider"
  echo "  Architecture: $arch"
  echo "  Version: $VERSION"

  vagrant cloud publish "$USERNAME/$BOX_NAME" "$VERSION" \
    "$provider" "../$file" \
    --architecture "$arch" \
    --release

  echo "✅ Uploaded: $file"
done

echo ""
echo "=========================================="
echo "🎉 All boxes uploaded successfully!"
echo "=========================================="
echo ""
echo "View your boxes at:"
echo "https://app.vagrantup.com/$USERNAME/boxes/$BOX_NAME"
echo ""
