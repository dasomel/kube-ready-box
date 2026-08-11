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

# 파일명 규칙은 upload-nixos.sh와 공유한다.
# shellcheck source=nixos/box-common.sh
. "${SCRIPT_DIR}/box-common.sh"

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

OUTPUT_DIR="output-vagrant"
DIST_DIR="dist"
CONFIG_FILE="configuration.nix"

PLATFORM=$(detect_arch)

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
  sbom                Generate SPDX SBOM from the NixOS system closure
  validate            Check syntax of configuration.nix (requires nix)
  help                Show this help message

EXAMPLES:
  $0 virtualbox       Build NixOS Vagrant box for VirtualBox
  $0 qemu             Build NixOS Vagrant box for QEMU/libvirt

PREREQUISITES:
  - Nix package manager installed (https://nixos.org/download.html)
  - Flakes enabled or nix-command enabled in nix.conf

NOTE:
  Nix가 없는 호스트(예: macOS)에서는 컨테이너로 대신 빌드할 수 있다:
    docker run --rm -v "\$(pwd)/nixos:/build" -w /build nixos/nix \\
      sh -c "nix --extra-experimental-features 'nix-command flakes' \\
        run github:nix-community/nixos-generators -- \\
        --format vagrant-virtualbox --configuration ./configuration.nix -o out"
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

# SPDX SBOM을 NixOS 시스템 클로저에서 생성한다. 이미지 빌드와 별개로 실행 가능.
generate_sbom() {
  check_nix
  mkdir -p "${DIST_DIR}"

  local out system closure
  out="${DIST_DIR}/$(sbom_filename "${PLATFORM}")"

  echo -e "${BLUE}=== Generating SBOM (SPDX) ===${NC}"
  system=$(nix-build '<nixpkgs/nixos>' -A system --no-out-link \
    --arg configuration "./${CONFIG_FILE}")
  closure=$(nix-store --query --requisites "$system")

  {
    printf '{\n'
    printf '  "spdxVersion": "SPDX-2.3",\n'
    printf '  "dataLicense": "CC0-1.0",\n'
    printf '  "SPDXID": "SPDXRef-DOCUMENT",\n'
    printf '  "name": "%s-%s",\n' "$BOX_PREFIX" "$PLATFORM"
    printf '  "creationInfo": { "creators": ["Tool: nix-store --query --requisites"] },\n'
    printf '  "packages": [\n'
    printf '%s\n' "$closure" | awk '
      {
        path = $0
        name = path
        sub(/^\/nix\/store\/[a-z0-9]+-/, "", name)
        printf "%s    { \"SPDXID\": \"SPDXRef-Package-%d\", \"name\": \"%s\", \"downloadLocation\": \"NOASSERTION\", \"licenseConcluded\": \"NOASSERTION\", \"externalRefs\": [{ \"referenceCategory\": \"PACKAGE-MANAGER\", \"referenceType\": \"purl\", \"referenceLocator\": \"pkg:nix%s\" }] }", (NR > 1 ? ",\n" : ""), NR, name, path
      }
      END { printf "\n" }'
    printf '  ]\n'
    printf '}\n'
  } >"$out"

  echo -e "${GREEN}✅ SBOM written: ${out} ($(printf '%s\n' "$closure" | wc -l | tr -d ' ') packages)${NC}"
}

build_box() {
  local format="$1"
  local provider artifact
  provider=$(format_to_provider "$format")
  if [ -n "$provider" ]; then
    artifact=$(box_filename "$PLATFORM" "$provider")
  else
    # raw-efi 등은 Vagrant 박스가 아니라 디스크 이미지다. .box 확장자를 붙이지 않는다.
    artifact=$(image_filename "$PLATFORM" "$format")
  fi
  check_nix

  echo -e "${BLUE}=== Building NixOS image (${format}) ===${NC}"
  mkdir -p "${OUTPUT_DIR}" "${DIST_DIR}"

  echo -e "${YELLOW}Running nixos-generators for format: ${format}...${NC}"
  nix run github:nix-community/nixos-generators -- \
    --format "${format}" \
    --configuration "./${CONFIG_FILE}" \
    -o "${OUTPUT_DIR}/${artifact}"

  if [ ! -e "${OUTPUT_DIR}/${artifact}" ]; then
    echo -e "${RED}❌ Build failed: Artifact ${OUTPUT_DIR}/${artifact} not found.${NC}"
    exit 1
  fi
  echo -e "${GREEN}✅ Build successful: ${OUTPUT_DIR}/${artifact}${NC}"

  # -o 결과는 /nix/store를 가리키는 심볼릭 링크다. 포맷에 따라 파일이 아니라
  # nixos.img를 담은 디렉터리일 수 있다(raw-efi). 디렉터리째 cp -rL 하면 store의
  # 읽기 전용 퍼미션 때문에 "Permission denied"로 죽으므로 실제 이미지만 꺼낸다.
  local src="${OUTPUT_DIR}/${artifact}"
  if [ -d "$src" ]; then
    local inner
    inner=$(find -L "$src" -maxdepth 1 -type f \( -name '*.img' -o -name '*.box' -o -name '*.qcow2' -o -name '*.vmdk' \) | head -1)
    if [ -z "$inner" ]; then
      echo -e "${RED}❌ ${src} 안에서 이미지 파일을 찾지 못했습니다.${NC}"
      exit 1
    fi
    src="$inner"
  fi
  cp -L "$src" "${DIST_DIR}/${artifact}"
  chmod u+w "${DIST_DIR}/${artifact}"
  echo -e "${GREEN}📦 Saved dereferenced copy to: ${DIST_DIR}/${artifact}${NC}"
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
  sbom)
    generate_sbom
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
