#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
#
# Vagrant Cloud NixOS Box Upload Script (v0.1.0)
set -e

VERSION="${VERSION:-0.1.0}"
BOX_DIR="$(cd "$(dirname "$0")/dist" && pwd)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║      📦 Vagrant Cloud NixOS Box Publish v${VERSION}               ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Version: ${VERSION}"
echo "Box Directory: ${BOX_DIR}"
echo "License: MIT (SPDX: MIT)"
echo ""

echo "Checking Vagrant Cloud login status..."
if ! vagrant cloud auth whoami 2>/dev/null; then
  echo "⚠️  whoami check failed — service token may still work. Will verify during publish."
fi
echo ""

upload_nixos_box() {
  local provider=$1
  local arch=$2
  local box_file="dasomel-nixos-kube-ready-${arch}-${provider}.box"
  local box_path="${BOX_DIR}/${box_file}"

  if [ ! -f "$box_path" ]; then
    echo "⚠️  Box file not found: ${box_file} in ${BOX_DIR} (skipping)"
    return 0
  fi

  local box_name="dasomel/nixos-kube-ready"
  local vagrant_provider="$provider"
  [ "$provider" = "vmware" ] && vagrant_provider="vmware_desktop"

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📤 Uploading: ${box_file}"
  echo "   Box: ${box_name} v${VERSION} (${vagrant_provider}, ${arch})"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  vagrant cloud publish "$box_name" "$VERSION" "$vagrant_provider" \
    "$box_path" \
    --architecture "$arch" \
    --version-description "Kubernetes-ready NixOS (Declarative Immutable OS) v${VERSION}

## License Information
- Distributed under the **MIT License** (SPDX-License-Identifier: MIT)
- Copyright (c) 2026 dasomel <dasomell@gmail.com>

## Features
- Base OS: **NixOS** (Declarative, Immutable Store Architecture)
- Pre-installed Container Runtimes: containerd, docker
- Pre-installed K8s Tools: kubectl, helm, cri-tools
- Storage & CSI Prerequisites: openiscsi, cryptsetup, lvm2, persistent eBPF (/sys/fs/bpf)
- Kernel & Sysctl Optimizations for Kubernetes workloads (swap disabled)

## Software Bill of Materials (SBOM) & Metadata
- SBOM Format: SPDX JSON / Nix Store Closure Manifest
- In-Guest Metadata: \`/etc/vagrant-box/info.txt\`, \`/etc/vagrant-box/LICENSE\`, \`/etc/vagrant-box/manifest.json\`

## Repository & Documentation
https://github.com/dasomel/kube-ready-box" \
    --force \
    --release \
    --short-description "K8s-ready NixOS v${VERSION} Declarative Box (MIT License)" \
  || {
    echo "❌ Upload failed: ${box_file}"
    return 1
  }

  echo "✅ Uploaded successfully: ${box_file}"
  echo ""
}

uploaded=0
failed=0

for provider in virtualbox vmware qemu libvirt; do
  for arch in arm64 amd64; do
    if upload_nixos_box "$provider" "$arch"; then
      ((uploaded++))
    else
      ((failed++))
    fi
  done
done

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
if [ $failed -eq 0 ]; then
  echo "║        ✅ NixOS Box Upload Process Complete (${uploaded} uploaded)     ║"
else
  echo "║        ⚠️  NixOS Box Upload Complete (${uploaded} ok, ${failed} failed) ║"
fi
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Vagrant Cloud URL: https://app.vagrantup.com/dasomel/boxes/nixos-kube-ready"
echo ""
echo "Usage:"
echo "  vagrant init dasomel/nixos-kube-ready"
echo "  vagrant up"
