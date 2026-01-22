#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 dasomel
set -e

#=========================================
# Vagrant Cloud Upload Script
# dasomel/ubuntu-24.04
#=========================================

USERNAME="dasomel"
BOX_NAME="ubuntu-24.04"
VERSION="${1:-1.0.0}"

if [ -z "$1" ]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 1.0.0"
  exit 1
fi

# Check if boxes exist
for box in ubuntu-24.04-virtualbox-amd64.box \
           ubuntu-24.04-virtualbox-arm64.box \
           ubuntu-24.04-vmware-amd64.box \
           ubuntu-24.04-vmware-arm64.box; do
  if [ ! -f "../$box" ]; then
    echo "Error: Box file not found: $box"
    echo "Please run './build.sh all' first"
    exit 1
  fi
done

echo "=========================================="
echo "Uploading dasomel/ubuntu-24.04 v${VERSION}"
echo "=========================================="

BOXES=(
  "virtualbox:amd64:ubuntu-24.04-virtualbox-amd64.box"
  "virtualbox:arm64:ubuntu-24.04-virtualbox-arm64.box"
  "vmware_desktop:amd64:ubuntu-24.04-vmware-amd64.box"
  "vmware_desktop:arm64:ubuntu-24.04-vmware-arm64.box"
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
