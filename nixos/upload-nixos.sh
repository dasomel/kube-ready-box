#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
#
# Vagrant Cloud NixOS Box Upload Script (v0.1.0)
set -e

VERSION="${VERSION:-0.1.0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 파일명 규칙은 build.sh와 공유한다.
# shellcheck source=nixos/box-common.sh
. "${SCRIPT_DIR}/box-common.sh"

BOX_DIR="${SCRIPT_DIR}/dist"
if [ ! -d "$BOX_DIR" ]; then
  echo "❌ Box directory not found: ${BOX_DIR}" >&2
  echo "   먼저 ./build.sh virtualbox 로 박스를 빌드하세요." >&2
  exit 1
fi

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

# 0=업로드, 2=대상 없음(건너뜀), 1=실패
upload_nixos_box() {
  local provider=$1
  local arch=$2
  local box_file box_path vagrant_provider
  box_file=$(box_filename "$arch" "$provider")
  box_path="${BOX_DIR}/${box_file}"

  if [ ! -f "$box_path" ]; then
    echo "⚠️  Box file not found: ${box_file} in ${BOX_DIR} (skipping)"
    return 2
  fi

  vagrant_provider="$provider"

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📤 Uploading: ${box_file}"
  echo "   Box: ${BOX_NAME} v${VERSION} (${vagrant_provider}, ${arch})"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  vagrant cloud publish "$BOX_NAME" "$VERSION" "$vagrant_provider" \
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

## In-Guest Metadata
- \`/etc/vagrant-box/info.txt\`, \`/etc/vagrant-box/LICENSE\`, \`/etc/vagrant-box/manifest.json\`
- SBOM (SPDX 2.3 JSON) is generated separately by \`nixos/build.sh sbom\` and published in the repository, not embedded in the box.

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
skipped=0
failed=0

# libvirt 박스는 Linux(vagrant-libvirt)와 macOS(vagrant-qemu)가 공유한다.
# virtualbox는 목록에 없다: nixpkgs가 게스트 확장용 pkgsi686Linux를 요구해 ARM64에서 만들 수 없다.
# 검증되지 않은 프로바이더를 실수로 공개하지 않도록 PROVIDERS로 범위를 좁힐 수 있다.
#   예: PROVIDERS=libvirt VERSION=0.1.1 ./upload-nixos.sh
PROVIDERS="${PROVIDERS:-libvirt vmware_desktop}"

for provider in $PROVIDERS; do
  for arch in arm64 amd64; do
    # set -e 아래에서 산술 증가식이 0을 반환해 스크립트를 죽이지 않도록 $((...)) 대입을 쓴다.
    set +e
    upload_nixos_box "$provider" "$arch"
    rc=$?
    set -e
    case "$rc" in
      0) uploaded=$((uploaded + 1)) ;;
      2) skipped=$((skipped + 1)) ;;
      *) failed=$((failed + 1)) ;;
    esac
  done
done

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  NixOS Box Upload: ${uploaded} uploaded, ${skipped} skipped, ${failed} failed"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# 아무것도 올리지 않은 실행을 성공으로 보고하지 않는다.
if [ "$failed" -gt 0 ]; then
  echo "❌ ${failed}개 업로드 실패" >&2
  exit 1
fi
if [ "$uploaded" -eq 0 ]; then
  echo "❌ 업로드된 박스가 없습니다. ${BOX_DIR}에 $(box_filename '<arch>' '<provider>') 형식의 파일이 필요합니다." >&2
  echo "   먼저 ./build.sh virtualbox 를 실행하세요." >&2
  exit 1
fi

echo "Vagrant Cloud URL: https://app.vagrantup.com/${BOX_NAME%%/*}/boxes/${BOX_NAME#*/}"
echo ""
echo "Usage:"
echo "  vagrant init ${BOX_NAME}"
echo "  vagrant up"
