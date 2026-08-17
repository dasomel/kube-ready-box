#!/bin/bash
# Vagrant Cloud Box 업로드 스크립트
# ext4/xfs 파일시스템 지원
# 실제 Terminal.app에서 실행하세요

set -e

VERSION="${VERSION:-0.2.3}"                            # Box semver (Vagrant Cloud release)
UBUNTU_VERSION="${UBUNTU_VERSION:-24.04}"  # Ubuntu version (24.04 or 26.04)
BOX_DIR="$(cd "$(dirname "$0")/packer/output-vagrant" && pwd)"
# 실수로 검증되지 않은 provider를 공개하지 않도록 업로드 범위를 제한할 수 있다.
# 예: PROVIDERS=vmware_desktop UBUNTU_VERSION=26.04 ./upload-boxes.sh
PROVIDERS="${PROVIDERS:-vmware_desktop virtualbox}"

# Parse arguments
FS_TARGET="both"
for arg in "$@"; do
  case "$arg" in
    --version=*)
      UBUNTU_VERSION="${arg#*=}"
      ;;
    ext4|xfs|both)
      FS_TARGET="$arg"
      ;;
  esac
done

# Validate Ubuntu version (mirror build.sh allowlist)
case "$UBUNTU_VERSION" in
  24.04 | 26.04) ;;
  *)
    echo "Error: invalid UBUNTU_VERSION '${UBUNTU_VERSION}' (use 24.04 or 26.04)" >&2
    exit 1
    ;;
esac

normalize_provider() {
  case "$1" in
    vmware | vmware_desktop) echo "vmware" ;;
    virtualbox) echo "virtualbox" ;;
    *)
      echo "Error: invalid provider '$1' in PROVIDERS (use vmware_desktop and/or virtualbox)" >&2
      return 1
      ;;
  esac
}

SELECTED_PROVIDERS=""
for raw_provider in $PROVIDERS; do
  provider=$(normalize_provider "$raw_provider")
  case " $SELECTED_PROVIDERS " in
    *" $provider "*) ;;
    *) SELECTED_PROVIDERS="${SELECTED_PROVIDERS} ${provider}" ;;
  esac
done
SELECTED_PROVIDERS="${SELECTED_PROVIDERS# }"

if [ -z "$SELECTED_PROVIDERS" ]; then
  echo "Error: PROVIDERS resolved to an empty set" >&2
  exit 1
fi

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║           📦 Vagrant Cloud Box 업로드 v${VERSION}                    ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Ubuntu: ${UBUNTU_VERSION}"
echo "Filesystem: ${FS_TARGET}"
echo "Providers: ${PROVIDERS}"
echo "Box directory: ${BOX_DIR}"
echo ""

# 로그인 확인 (service 토큰은 whoami/account 조회가 실패할 수 있으므로 경고만;
# 실제 인증 유효성은 'vagrant cloud publish'(org 명시)에서 판정한다)
echo "로그인 상태 확인..."
if ! vagrant cloud auth whoami 2>/dev/null; then
    echo "⚠️  whoami 확인 실패 — service 토큰은 정상일 수 있음. publish 단계에서 실제 인증을 확인합니다."
fi
echo ""

upload_box() {
    local fs=$1
    local provider=$2
    local arch=$3
    local fs_upper=$(echo "$fs" | tr '[:lower:]' '[:upper:]')
    local box_file="ubuntu-${UBUNTU_VERSION}-${fs}-${provider}-${arch}.box"
    local box_path="${BOX_DIR}/${box_file}"

    if [ ! -f "$box_path" ]; then
        echo "⚠️  Box not found: ${box_file} (skipping)"
        return 2
    fi

    local box_name="dasomel/ubuntu-${UBUNTU_VERSION}-${fs}"
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
        --version-description "Kubernetes-ready Ubuntu ${UBUNTU_VERSION} LTS (${fs_upper} filesystem) v${VERSION}

## Filesystem: ${fs_upper}
- ext4: Mature, stable, supports online shrink
- xfs: Better for large files, parallel I/O, K8s ephemeral storage quota

## Features
- Ubuntu ${UBUNTU_VERSION} LTS with OS optimizations for Kubernetes
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
        --short-description "K8s-ready Ubuntu ${UBUNTU_VERSION} (${fs_upper}) Vagrant Box" \
    || {
        echo "❌ Upload failed: ${box_file}"
        return 1
    }

    echo "✅ Uploaded: ${box_file}"
    echo ""
}

# 업로드 실행
uploaded=0
skipped=0
failed=0

for fs in ext4 xfs; do
    if [ "$FS_TARGET" != "both" ] && [ "$FS_TARGET" != "$fs" ]; then
        continue
    fi

    for provider in $SELECTED_PROVIDERS; do
        for arch in arm64 amd64; do
            set +e
            upload_box "$fs" "$provider" "$arch"
            rc=$?
            set -e
            case "$rc" in
                0) uploaded=$((uploaded + 1)) ;;
                2) skipped=$((skipped + 1)) ;;
                *) failed=$((failed + 1)) ;;
            esac
        done
    done
done

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
if [ $failed -eq 0 ]; then
    echo "║      ✅ 업로드 완료 (${uploaded} uploaded, ${skipped} skipped)         ║"
else
    echo "║  ⚠️  업로드 완료 (${uploaded} uploaded, ${skipped} skipped, ${failed} failed) ║"
fi
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Vagrant Cloud:"
echo "  ext4: https://app.vagrantup.com/dasomel/boxes/ubuntu-${UBUNTU_VERSION}-ext4"
echo "  xfs:  https://app.vagrantup.com/dasomel/boxes/ubuntu-${UBUNTU_VERSION}-xfs"
echo ""
echo "사용법:"
echo "  vagrant init dasomel/ubuntu-${UBUNTU_VERSION}-ext4   # ext4 filesystem"
echo "  vagrant init dasomel/ubuntu-${UBUNTU_VERSION}-xfs    # xfs filesystem"
echo "  vagrant up --provider=vmware_desktop"
echo ""

if [ "$failed" -gt 0 ]; then
    echo "❌ ${failed}개 업로드 실패" >&2
    exit 1
fi
if [ "$uploaded" -eq 0 ]; then
    echo "❌ 업로드된 박스가 없습니다. PROVIDERS=${PROVIDERS}, FS_TARGET=${FS_TARGET}, BOX_DIR=${BOX_DIR}를 확인하세요." >&2
    exit 1
fi
