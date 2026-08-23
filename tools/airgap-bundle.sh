#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
set -euo pipefail

# Build-input bundle helper for reproducible, air-gapped kube-ready-box builds.
# The bundle is independent from the host apt configuration.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ROOT="${BUNDLE_ROOT:-$ROOT/build-inputs}"
UBUNTU_VERSION="${UBUNTU_VERSION:-24.04}"
ARCH="${ARCH:-amd64}"
BUNDLE_DIR="$BUNDLE_ROOT/ubuntu-${UBUNTU_VERSION}/${ARCH}"
PACKAGE_LIST="$BUNDLE_DIR/packages.txt"
MANIFEST="$BUNDLE_DIR/manifest.env"
CHECKSUMS="$BUNDLE_DIR/SHA256SUMS"

packages=(
  socat conntrack ipset ipvsadm ebtables
  open-iscsi cryptsetup dmsetup
  chrony auditd apparmor-utils lvm2 xfsprogs
)

usage() {
  cat <<USAGE
Usage: $(basename "$0") <prepare|verify|list>

Environment:
  UBUNTU_VERSION=24.04|26.04
  ARCH=amd64|arm64
  BUNDLE_ROOT=build-inputs

prepare downloads the pinned ISO, apt packages and signing key into a
versioned bundle, then writes a manifest and SHA256SUMS. It requires network
access only while preparing the bundle.

verify performs an offline-only integrity check. It does not contact a
package repository or GitHub.
USAGE
}

fail() { echo "ERROR: $*" >&2; exit 1; }

validate_target() {
  case "$UBUNTU_VERSION" in 24.04|26.04) ;; *) fail "unsupported Ubuntu version: $UBUNTU_VERSION" ;; esac
  case "$ARCH" in amd64|arm64) ;; *) fail "unsupported architecture: $ARCH" ;; esac
}

prepare() {
  validate_target
  command -v curl >/dev/null || fail "curl is required"
  command -v sha256sum >/dev/null || fail "sha256sum is required"
  command -v apt-get >/dev/null || fail "apt-get is required"
  mkdir -p "$BUNDLE_DIR"/{iso,debs,keys,binaries,trivy-db}

  # arm64 live-server ISO 는 releases.ubuntu.com 에 없다(404). cdimage 에만 있다.
  # 이전에는 두 아키텍처 모두 releases.ubuntu.com 을 써서 arm64 번들 생성이 불가능했다.
  local point_release iso_base iso_dir iso_url
  if [ "$UBUNTU_VERSION" = "24.04" ]; then
    # point_release 는 packer/plugins.pkr.hcl 의 ISO URL 에서 뽑아온다(단일 source of
    # truth). 과거 이 값을 여기에 별도로 하드코딩했다가 plugins.pkr.hcl 이 24.04.3 을
    # 가리키는 동안 여기는 24.04.4 로 방치되어, 번들이 packer 가 실제로 쓰는 ISO 와
    # 다른 point release 로 만들어질 수 있었다.
    local plugins_hcl="$ROOT/packer/plugins.pkr.hcl"
    local extracted=""
    if [ -f "$plugins_hcl" ]; then
      extracted="$(grep -oE '24\.04\.[0-9]+' "$plugins_hcl" | head -1 || true)"
    fi
    case "$extracted" in
      24.04.*)
        point_release="$extracted"
        ;;
      *)
        point_release="24.04.4"
        echo "WARNING: could not extract point release from $plugins_hcl; falling back to hardcoded $point_release (may drift from the actual Packer ISO)" >&2
        ;;
    esac
  else
    point_release="26.04"
  fi
  iso_base="ubuntu-${point_release}-live-server-${ARCH}.iso"
  if [ "$ARCH" = "arm64" ]; then
    iso_dir="https://cdimage.ubuntu.com/releases/${point_release}/release"
  else
    iso_dir="https://releases.ubuntu.com/${point_release}"
  fi
  iso_url="${iso_dir}/${iso_base}"
  local iso_file="$BUNDLE_DIR/iso/${iso_base}"
  curl -fL --retry 3 -o "$iso_file" "$iso_url"

  # 업스트림 SHA256SUMS 와 대조한다. 이전에는 받은 파일의 해시를 기록만 해서,
  # 잘못 받아진 ISO 도 그대로 정답으로 봉인됐다(#7 "재현 가능한 동일 input").
  echo "Verifying ISO against upstream SHA256SUMS..."
  local upstream_sums expected actual
  upstream_sums="$BUNDLE_DIR/iso/SHA256SUMS.upstream"
  curl -fL --retry 3 -o "$upstream_sums" "${iso_dir}/SHA256SUMS"
  expected=$(awk -v f="*${iso_base}" '$2 == f {print $1; exit}' "$upstream_sums")
  [ -n "$expected" ] || expected=$(awk -v f="${iso_base}" '$2 == f {print $1; exit}' "$upstream_sums")
  [ -n "$expected" ] || fail "upstream SHA256SUMS 에 ${iso_base} 항목이 없습니다"
  actual=$(sha256sum "$iso_file" | awk '{print $1}')
  [ "$expected" = "$actual" ] || fail "ISO 체크섬 불일치: expected=$expected actual=$actual"
  echo "ISO checksum OK: $actual"

  printf '%s\n' "${packages[@]}" > "$PACKAGE_LIST"
  local deb_arch="$ARCH"
  while IFS= read -r pkg; do
    (cd "$BUNDLE_DIR/debs" && apt-get download "${pkg}:${deb_arch}")
done < "$PACKAGE_LIST"

  curl -fL --retry 3 -o "$BUNDLE_DIR/keys/ubuntu-archive-keyring.gpg" \
    https://archive.ubuntu.com/ubuntu/project/ubuntu-archive-keyring.gpg

  cat > "$MANIFEST" <<EOF_MANIFEST
schema_version=1
ubuntu_version=$UBUNTU_VERSION
architecture=$ARCH
iso_url=$iso_url
iso_sha256=$actual
package_count=$(wc -l < "$PACKAGE_LIST")
bundle_created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF_MANIFEST

  (cd "$BUNDLE_DIR" && find iso debs keys binaries trivy-db -type f -print0 | sort -z | xargs -0 sha256sum > "$CHECKSUMS")
  echo "Prepared: $BUNDLE_DIR"
  echo "Manifest: $MANIFEST"
  echo "Checksums: $CHECKSUMS"
}

verify() {
  validate_target
  [ -s "$MANIFEST" ] || fail "missing manifest: $MANIFEST"
  [ -s "$CHECKSUMS" ] || fail "missing checksums: $CHECKSUMS"
  (cd "$BUNDLE_DIR" && sha256sum -c "$CHECKSUMS")
  [ -s "$PACKAGE_LIST" ] || fail "missing package lock: $PACKAGE_LIST"
  [ -s "$BUNDLE_DIR/keys/ubuntu-archive-keyring.gpg" ] || fail "missing Ubuntu archive key"
  echo "Offline bundle verification: PASS"
  echo "No network access was used by verify."
}

list_bundle() {
  validate_target
  [ -d "$BUNDLE_DIR" ] || fail "bundle not found: $BUNDLE_DIR"
  find "$BUNDLE_DIR" -maxdepth 4 -type f -print | sort
}

case "${1:-}" in
  prepare) prepare ;;
  verify) verify ;;
  list) list_bundle ;;
  *) usage; exit 2 ;;
esac
