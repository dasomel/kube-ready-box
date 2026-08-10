#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
set -e

#=========================================
# NixOS Kube-Ready Vagrant Box Build Script
# dasomel/nixos-kube-ready
#=========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

OUTPUT_DIR="output-vagrant"
DIST_DIR="dist"
CONFIG_FILE="configuration.nix"

detect_platform() {
  local arch
  arch=$(uname -m)
  if [ "$arch" = "arm64" ]; then
    echo "arm64"
  elif [ "$arch" = "x86_64" ]; then
    echo "amd64"
  else
    echo "unknown"
  fi
}

PLATFORM=$(detect_platform)

show_usage() {
  cat <<EOF
Usage: $0 [FORMAT_OPTION]

Build NixOS Kubernetes-ready Vagrant boxes using nixos-generators.

CURRENT PLATFORM:
  Platform: ${PLATFORM} ($(uname -m))

OPTIONS:
  virtualbox          Build VirtualBox Vagrant Box (--format vagrant-virtualbox)
  qemu                Build QEMU/libvirt Vagrant Box (--format vagrant-libvirt)
  raw                 Build Raw QEMU Disk Image (--format raw-efi)
  validate            Check syntax of configuration.nix (requires nix)
  help                Show this help message

EXAMPLES:
  $0 virtualbox       Build NixOS Vagrant box for VirtualBox
  $0 qemu             Build NixOS Vagrant box for QEMU/libvirt

PREREQUISITES:
  - Nix package manager installed (https://nixos.org/download.html)
  - Flakes enabled or nix-command enabled in nix.conf
EOF
}

check_nix() {
  if ! command -v nix >/dev/null 2>&1; then
    echo -e "${RED}Error: 'nix' command is not installed or not in PATH.${NC}"
    echo -e "${YELLOW}To install Nix, run:${NC}"
    echo -e "  curl -L https://nixos.org/nix/install | sh"
    echo -e "${YELLOW}And ensure experimental features 'nix-command flakes' are enabled in ~/.config/nix/nix.conf:${NC}"
    echo -e "  experimental-features = nix-command flakes"
    exit 1
  fi
}

validate_config() {
  echo -e "${BLUE}=== Validating ${CONFIG_FILE} ===${NC}"
  check_nix
  nix-instantiate --eval --expr "import ./${CONFIG_FILE} { config = {}; pkgs = import <nixpkgs> {}; modulesPath = \"\"; }" >/dev/null
  echo -e "${GREEN}✅ Syntax validation passed!${NC}"
}

build_box() {
  local format="$1"
  local box_name="dasomel-nixos-kube-ready-${PLATFORM}-${format}.box"

  check_nix

  echo -e "${BLUE}=== Building NixOS Vagrant Box (${format}) ===${NC}"
  mkdir -p "${OUTPUT_DIR}" "${DIST_DIR}"

  echo -e "${YELLOW}Running nixos-generators for format: ${format}...${NC}"
  nix run github:nix-community/nixos-generators -- \
    --format "${format}" \
    --configuration "./${CONFIG_FILE}" \
    -o "${OUTPUT_DIR}/${box_name}"

  if [ -e "${OUTPUT_DIR}/${box_name}" ]; then
    echo -e "${GREEN}✅ Build successful: ${OUTPUT_DIR}/${box_name}${NC}"
    cp -rL "${OUTPUT_DIR}/${box_name}" "${DIST_DIR}/${box_name}"
    echo -e "${GREEN}📦 Saved dereferenced copy to: ${DIST_DIR}/${box_name}${NC}"
  else
    echo -e "${RED}❌ Build failed: Artifact ${OUTPUT_DIR}/${box_name} not found.${NC}"
    exit 1
  fi
}

FORMAT="${1:-help}"

case "$FORMAT" in
  virtualbox)
    build_box "vagrant-virtualbox"
    ;;
  qemu|libvirt)
    build_box "vagrant-libvirt"
    ;;
  raw)
    build_box "raw-efi"
    ;;
  validate)
    validate_config
    ;;
  help|--help|-h)
    show_usage
    ;;
  *)
    echo -e "${RED}Error: Unknown format option '$FORMAT'${NC}"
    show_usage
    exit 1
    ;;
esac
