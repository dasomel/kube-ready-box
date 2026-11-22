#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
#
# tools/release/*.sh 가 source 하는 공용 함수. 직접 실행하지 않는다.

# 저장소 루트는 이 파일 위치에서 구한다(절대 경로를 박지 않는다).
release_repo_root() { (cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd); }

# 정기 스캔 워크플로가 고정한 Trivy 버전/sha256 을 그대로 읽는다.
# D1: 버전을 이 스크립트에 따로 적으면 워크플로와 어긋난다(스캔 결과가 CI 와 다른 도구로 나온다).
#     한 곳(box-cve-scan.yml)만 고치면 되게 한다. 못 읽으면 실패(fail closed).
trivy_pin() { # 출력: "<version> <linux-64bit sha256>"
  local wf ver sha
  wf="$(release_repo_root)/.github/workflows/box-cve-scan.yml"
  [ -f "$wf" ] || { echo "workflow not found: $wf" >&2; return 1; }
  ver=$(sed -n 's/^  TRIVY_VERSION: *\([0-9][0-9.]*\) *$/\1/p' "$wf" | head -1)
  sha=$(sed -n 's/^  TRIVY_SHA256: *\([0-9a-f]\{64\}\) *$/\1/p' "$wf" | head -1)
  [ -n "$ver" ] && [ -n "$sha" ] || { echo "TRIVY_VERSION/TRIVY_SHA256 not found in $wf" >&2; return 1; }
  echo "$ver $sha"
}

# <short>-<provider>-<arch>-<version>.box 를 분해한다. 출력: "<short> <provider> <arch> <version>".
# short = ubuntu-24.04-ext4 | rocky-9-xfs ... (스캔/부팅 검증 대상 계열만 받는다).
parse_box_name() { # $1 = 파일 이름 또는 경로
  local re='^((ubuntu-[0-9]+\.[0-9]+|rocky-[0-9]+)-(ext4|xfs))-(virtualbox|vmware_desktop|libvirt)-(amd64|arm64)-([0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?)\.box$'
  local base
  base=$(basename "$1")
  [[ "$base" =~ $re ]] || return 1
  echo "${BASH_REMATCH[1]} ${BASH_REMATCH[4]} ${BASH_REMATCH[5]} ${BASH_REMATCH[6]}"
}

# 스캔 러너: macOS 호스트에서는 Lima 인스턴스(SCAN_LIMA)가 Linux 를 대신한다.
# Lima 는 $HOME 을 같은 경로로 읽기 전용 마운트하므로 박스/저장소는 $HOME 아래에 있어야 하고,
# 쓰기가 필요한 작업 디렉터리는 VM 안의 /tmp 를 쓴다.
SCAN_LIMA=${SCAN_LIMA:-krbscan}
# 스크립트 한 덩어리를 문자열 하나로 넘긴다(값은 호출자가 printf %q 로 미리 끼워 넣는다).
vm_run() { limactl shell "$SCAN_LIMA" -- bash -c "$1"; }
