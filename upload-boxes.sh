#!/bin/bash
# Vagrant Cloud Box 업로드 스크립트
# ext4/xfs 파일시스템 지원
# 실제 Terminal.app에서 실행하세요

set -e

VERSION="0.2.2"
BOX_DIR="$(cd "$(dirname "$0")/packer/output-vagrant" && pwd)"

# 업로드할 파일시스템 선택 (기본: both)
FS_TARGET="${1:-both}"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║           📦 Vagrant Cloud Box 업로드 v${VERSION}                    ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Filesystem: ${FS_TARGET}"
echo "Box directory: ${BOX_DIR}"
echo ""

# 로그인 확인
echo "로그인 상태 확인..."
vagrant cloud auth whoami || {
    echo "❌ 로그인되어 있지 않습니다!"
    echo "실행: vagrant cloud auth login --token YOUR_TOKEN"
    exit 1
}
echo ""

upload_box() {
    local fs=$1
    local provider=$2
    local arch=$3
    local fs_upper=$(echo "$fs" | tr '[:lower:]' '[:upper:]')
    local box_file="ubuntu-24.04-${fs}-${provider}-${arch}.box"
    local box_path="${BOX_DIR}/${box_file}"

    if [ ! -f "$box_path" ]; then
        echo "⚠️  Box not found: ${box_file} (skipping)"
        return 0
    fi

    local box_name="dasomel/ubuntu-24.04-${fs}"
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
        --version-description "Kubernetes-ready Ubuntu 24.04 LTS (${fs_upper} filesystem) v${VERSION}

## Filesystem: ${fs_upper}
- ext4: Mature, stable, supports online shrink
- xfs: Better for large files, parallel I/O, K8s ephemeral storage quota

## Features
- Ubuntu 24.04 LTS with OS optimizations for Kubernetes
- Multi-architecture support (AMD64, ARM64)
- Multi-provider support (VirtualBox, VMware)
- 1TB disk with auto-extension at boot (thin provisioning)
- Filesystem selection: ext4 or xfs

## Documentation
https://github.com/dasomel/kube-ready-box

## CHANGELOG
https://github.com/dasomel/kube-ready-box/blob/main/CHANGELOG.md" \
        --force \
        --release \
        --short-description "K8s-ready Ubuntu 24.04 (${fs_upper}) Vagrant Box" \
    || {
        echo "❌ Upload failed: ${box_file}"
        return 1
    }

    echo "✅ Uploaded: ${box_file}"
    echo ""
}

# 업로드 실행
uploaded=0
failed=0

for fs in ext4 xfs; do
    if [ "$FS_TARGET" != "both" ] && [ "$FS_TARGET" != "$fs" ]; then
        continue
    fi

    for provider in vmware virtualbox; do
        for arch in arm64 amd64; do
            if upload_box "$fs" "$provider" "$arch"; then
                ((uploaded++))
            else
                ((failed++))
            fi
        done
    done
done

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
if [ $failed -eq 0 ]; then
    echo "║              ✅ 업로드 완료! (${uploaded} boxes)                     ║"
else
    echo "║              ⚠️  업로드 완료 (${uploaded} ok, ${failed} failed)              ║"
fi
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Vagrant Cloud:"
echo "  ext4: https://app.vagrantup.com/dasomel/boxes/ubuntu-24.04-ext4"
echo "  xfs:  https://app.vagrantup.com/dasomel/boxes/ubuntu-24.04-xfs"
echo ""
echo "사용법:"
echo "  vagrant init dasomel/ubuntu-24.04-ext4   # ext4 filesystem"
echo "  vagrant init dasomel/ubuntu-24.04-xfs    # xfs filesystem"
echo "  vagrant up --provider=vmware_desktop"
echo ""
