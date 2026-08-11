#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
#
# 박스 파일명 규칙의 단일 진실 공급원.
# build.sh(생성)와 upload-nixos.sh(소비)가 이름을 각자 조립하면 어긋나므로 여기서만 만든다.

# shellcheck disable=SC2034  # 소비처는 이 파일을 source 하는 upload-nixos.sh
BOX_NAME="dasomel/nixos-kube-ready"
BOX_PREFIX="dasomel-nixos-kube-ready"

# nixos-generators 포맷 -> Vagrant 프로바이더. 박스가 아닌 포맷(raw-efi 등)은 빈 문자열.
format_to_provider() {
  case "$1" in
    vagrant-virtualbox) echo "virtualbox" ;;
    vagrant-libvirt) echo "libvirt" ;;
    *) echo "" ;;
  esac
}

# uname -m은 macOS에서 arm64, Linux에서 aarch64를 반환한다. 둘 다 arm64로 정규화.
detect_arch() {
  case "$(uname -m)" in
    arm64 | aarch64) echo "arm64" ;;
    x86_64 | amd64) echo "amd64" ;;
    *) echo "unknown" ;;
  esac
}

# box_filename <arch> <provider>
box_filename() {
  printf '%s-%s-%s.box' "$BOX_PREFIX" "$1" "$2"
}

# image_filename <arch> <format>  (박스가 아닌 raw 디스크 이미지용)
image_filename() {
  printf '%s-%s-%s.img' "$BOX_PREFIX" "$1" "$2"
}

# sbom_filename <arch>
sbom_filename() {
  printf '%s-%s.sbom.spdx.json' "$BOX_PREFIX" "$1"
}
