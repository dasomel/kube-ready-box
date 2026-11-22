#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
#
# macOS 호스트에서 박스 CVE 스캔을 돌릴 Lima Linux VM 을 만든다(이미 있으면 그대로 두고
# 도구만 맞춘다). tools/release/verify-candidate.sh 의 scan 단계가 이 VM 을 쓴다.
#
# usage: tools/release/setup-scan-vm.sh [--dry-run]
#   SCAN_LIMA=krbscan   인스턴스 이름
# 설치: qemu-utils lvm2 xfsprogs python3 rpm curl + Trivy(.github/workflows/box-cve-scan.yml 의 고정 버전)
#
# D1: Trivy 는 워크플로가 고정한 버전만 설치한다. 워크플로의 sha256 은 Linux-64bit 용 하나뿐이라
#     arm64 tarball 은 릴리스의 trivy_<ver>_checksums.txt 로 검증하되, 그 checksums.txt 가 변조되지
#     않았음을 "Linux-64bit 줄이 워크플로의 고정 sha256 과 같은가"로 확인한다(고정값에 묶는다).
#     하나라도 어긋나면 설치하지 않는다(fail closed). escape hatch 없음: 버전을 올리려면 워크플로의
#     TRIVY_VERSION/TRIVY_SHA256 을 먼저 고친다.
set -euo pipefail

# shellcheck source=tools/release/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

DRY_RUN=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=1 ;;
  -h|--help) sed -n '/^# usage:/,/^# 설치:/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "unknown option: $1" >&2; exit 64 ;;
esac

read -r TRIVY_VERSION TRIVY_SHA256 < <(trivy_pin)
START="limactl start --name=$SCAN_LIMA --tty=false --cpus=2 --memory=4 --disk=40 --vm-type=vz template://ubuntu-24.04"
echo "scan VM: $SCAN_LIMA, trivy $TRIVY_VERSION (pinned in box-cve-scan.yml)"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRYRUN would run: $START   (only when the instance does not exist)"
  echo "DRYRUN would install: qemu-utils lvm2 xfsprogs python3 rpm curl + trivy $TRIVY_VERSION (sha256-verified)"
  exit 0
fi
command -v limactl >/dev/null || { echo "limactl not found (brew install lima)" >&2; exit 1; }

status=$(limactl list --format '{{.Status}}' "$SCAN_LIMA" 2>/dev/null || true)
case "$status" in
  Running) echo "instance already running" ;;
  Stopped) limactl start "$SCAN_LIMA" ;;
  "")      $START ;;
  *)       echo "instance $SCAN_LIMA is in state '$status'; fix it with limactl first" >&2; exit 1 ;;
esac

# 값은 printf %q 로 끼워 넣는다(limactl shell 은 인자를 다시 풀 수 있다).
vm_script="TRIVY_VERSION=$(printf %q "$TRIVY_VERSION"); TRIVY_SHA256=$(printf %q "$TRIVY_SHA256")
$(cat <<'EOF'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
sudo apt-get -qq update
sudo apt-get -qq install -y qemu-utils lvm2 xfsprogs python3 rpm curl ca-certificates
have=$(trivy --version 2>/dev/null | sed -n '1s/^Version: *//p' || true)
if [ "$have" = "$TRIVY_VERSION" ]; then echo "trivy $have already installed"; exit 0; fi
case "$(uname -m)" in
  aarch64|arm64) asset=Linux-ARM64 ;;
  x86_64) asset=Linux-64bit ;;
  *) echo "unsupported arch $(uname -m)" >&2; exit 1 ;;
esac
base="https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
curl -fsSL --retry 3 -o "$tmp/sums" "${base}/trivy_${TRIVY_VERSION}_checksums.txt"
curl -fsSL --retry 3 -o "$tmp/trivy.tgz" "${base}/trivy_${TRIVY_VERSION}_${asset}.tar.gz"
anchor=$(awk -v f="trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" '$2==f{print $1}' "$tmp/sums")
[ "$anchor" = "$TRIVY_SHA256" ] || { echo "checksums.txt Linux-64bit entry '$anchor' != pinned $TRIVY_SHA256" >&2; exit 1; }
want=$(awk -v f="trivy_${TRIVY_VERSION}_${asset}.tar.gz" '$2==f{print $1}' "$tmp/sums")
[ -n "$want" ] || { echo "no checksum for ${asset} in checksums.txt" >&2; exit 1; }
echo "$want  $tmp/trivy.tgz" | sha256sum -c -
sudo tar -xzf "$tmp/trivy.tgz" -C /usr/local/bin trivy
trivy --version | head -1
EOF
)"
vm_run "$vm_script"
echo "scan VM ready: SCAN_LIMA=$SCAN_LIMA"
