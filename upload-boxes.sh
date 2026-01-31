#!/bin/bash
# Vagrant Cloud Box 업로드 스크립트
# 실제 Terminal.app에서 실행하세요

set -e

cd "$(dirname "$0")/packer/output-vagrant"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║           📦 Vagrant Cloud Box 업로드                          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# 로그인 확인
echo "로그인 상태 확인..."
vagrant cloud auth whoami || {
    echo "❌ 로그인되어 있지 않습니다!"
    echo "실행: vagrant cloud auth login --token YOUR_TOKEN"
    exit 1
}

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📤 1/2: VMware ARM64 업로드 중... (2.3GB, 시간 소요)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 이미 업로드된 경우 건너뛰기 (버전이 이미 릴리즈된 경우)
if vagrant cloud search dasomel/ubuntu-24.04 --json 2>/dev/null | grep -q "vmware_desktop"; then
    echo "ℹ️  VMware provider already exists, skipping..."
else
    vagrant cloud publish dasomel/ubuntu-24.04 0.1.1 vmware_desktop \
      ubuntu-24.04-vmware-arm64.box \
      --architecture arm64 \
      --version-description "Initial release - Kubernetes-ready Ubuntu 24.04 LTS

## What's New
- Ubuntu 24.04 LTS base with cloud-init
- Multi-architecture support (AMD64, ARM64)
- Multi-provider support (VirtualBox, VMware)
- Comprehensive OS optimizations for K8s workloads
- MIT License with SBOM included

## Features
- Kernel tuning for network, memory, filesystem
- Resource limits configured (file descriptors, processes, memory locks)
- K8s prerequisites: swap disabled, kernel modules, IP forwarding
- Disk I/O and network optimizations
- Ubuntu 24.04 specific tuning (THP, systemd-oomd)

## Documentation
https://github.com/dasomel/kube-ready-box

## CHANGELOG
https://github.com/dasomel/kube-ready-box/blob/main/CHANGELOG.md" \
      --release \
      --short-description "Kubernetes-ready Ubuntu 24.04 LTS Vagrant Box with OS-level optimizations"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📤 2/2: VirtualBox ARM64 업로드 중... (2.3GB, 시간 소요)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# VirtualBox provider 추가 (기존 버전에)
# 이미 존재하면 무시
vagrant cloud version provider create dasomel/ubuntu-24.04 0.1.1 virtualbox \
  --architecture arm64 2>/dev/null || echo "ℹ️  VirtualBox provider already exists, continuing..."

vagrant cloud version provider upload dasomel/ubuntu-24.04 0.1.1 virtualbox \
  arm64 ubuntu-24.04-virtualbox-arm64.box

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              ✅ 업로드 완료!                                   ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Vagrant Cloud: https://app.vagrantup.com/dasomel/boxes/ubuntu-24.04"
echo ""
echo "테스트:"
echo "  vagrant init dasomel/ubuntu-24.04"
echo "  vagrant up --provider=vmware_desktop"
echo ""
