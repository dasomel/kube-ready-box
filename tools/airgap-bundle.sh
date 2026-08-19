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

  local iso_url
  if [ "$UBUNTU_VERSION" = "24.04" ]; then
    iso_url="https://releases.ubuntu.com/24.04.4/ubuntu-24.04.4-live-server-${ARCH}.iso"
  else
    iso_url="https://releases.ubuntu.com/26.04/ubuntu-26.04-live-server-${ARCH}.iso"
  fi
  local iso_file="$BUNDLE_DIR/iso/$(basename "$iso_url")"
  curl -fL --retry 3 -o "$iso_file" "$iso_url"

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
