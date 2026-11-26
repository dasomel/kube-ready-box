#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 dasomel
set -e

echo "=== 03-os-packages.sh: Install Recommended Packages ==="

# 필수 패키지
echo "Installing essential system packages..."
apt-get install -y \
  linux-tools-common \
  linux-tools-generic \
  sysstat \
  iotop \
  iftop \
  nload \
  nethogs

# D-fetch: github.com/<repo>/releases/download/... 가 2026-11-08 에 504 를 반환했다
# (api.github.com 의 release asset 엔드포인트는 정상). 먼저 일반 URL 을 -f + 재시도로
# 받고, 실패하면 API asset 경로로 폴백한다. 비용: 실패 시 API 호출 2회 추가(비인증
# 60회/시간 한도 내). 되돌리기: 폴백 분기를 지우면 이전 동작. 어느 경로든 호출부의
# 고정 SHA-256 검증(sha256sum -c)이 그대로 적용되므로 무결성 검증은 약해지지 않는다.
# (스크립트가 게스트에 개별 업로드되어 공용 파일을 쓸 수 없어 함수를 3개 스크립트에 동일하게 둔다.)
fetch_release_asset() {
  local repo="$1" tag="$2" asset="$3" out="$4" py id
  if curl -fsSL --retry 3 --retry-delay 5 --connect-timeout 20 -o "$out" \
      "https://github.com/${repo}/releases/download/${tag}/${asset}"; then
    return 0
  fi
  rm -f "$out"
  echo "  releases/download failed for ${repo} ${tag} ${asset}; falling back to api.github.com asset API" >&2
  for py in python3 /usr/libexec/platform-python; do
    command -v "$py" >/dev/null 2>&1 && break
    py=""
  done
  if [ -z "$py" ]; then
    echo "  no python3/platform-python available to parse the release JSON" >&2
    return 1
  fi
  id=$(curl -fsSL --retry 3 --retry-delay 5 --connect-timeout 20 \
      "https://api.github.com/repos/${repo}/releases/tags/${tag}" \
    | "$py" -c 'import json,sys
for a in json.load(sys.stdin).get("assets", []):
    if a.get("name") == sys.argv[1]:
        print(a["id"])
        break' "$asset") || id=""
  if [ -z "$id" ]; then
    echo "  asset '${asset}' not found in ${repo} release ${tag}" >&2
    return 1
  fi
  if ! curl -fsSL --retry 3 --retry-delay 5 --connect-timeout 20 \
      -H 'Accept: application/octet-stream' -o "$out" \
      "https://api.github.com/repos/${repo}/releases/assets/${id}"; then
    rm -f "$out"
    return 1
  fi
  echo "  fetched ${asset} via api.github.com asset ${id}" >&2
}

# dool (dstat replacement) - not in Ubuntu 24.04 repos, install from a pinned
# GitHub release .deb (#30 공급망 고정). "master" 브랜치 raw 스크립트를 그대로
# curl|install 하던 이전 방식은 업스트림이 조용히 바뀌면 그대로 흘러들어오는
# floating dependency였다.
echo "Installing dool (dstat replacement)..."
DOOL_VERSION="${DOOL_VERSION:-1.3.8}"
DOOL_SHA256="${DOOL_SHA256:-818c833551b365a89f6ae29f07df5ea34588563e2eebaf3b2f93d64f6c9787fd}"
fetch_release_asset scottchiefbaker/dool "v${DOOL_VERSION}" "dool-${DOOL_VERSION}.deb" /tmp/dool.deb
echo "${DOOL_SHA256}  /tmp/dool.deb" | sha256sum -c -
dpkg -i /tmp/dool.deb
rm -f /tmp/dool.deb
echo "  dool installed: $(dool --version 2>&1 | head -1)"

# 네트워크 진단 도구
echo "Installing network diagnostic tools..."
apt-get install -y \
  ipvsadm \
  ipset \
  conntrack \
  ethtool \
  tcpdump \
  nmap

# K8s 에코시스템 도구
echo "Installing Kubernetes ecosystem tools..."
apt-get install -y \
  jq \
  bzip2 \
  tar \
  bash-completion \
  nfs-common \
  sshpass \
  apparmor-utils

# yq (mikefarah/yq) - YAML processor for K8s manifests
# "latest" 는 빌드 시점마다 달라져 재현 가능한 빌드를 깨뜨린다(#30 공급망 고정).
# YQ_VERSION 으로 고정하고, 필요 시 환경변수로 override 한다. 체크섬은 yq의
# releases/<tag>/checksums 파일에서 직접 뽑아 미리 고정한 값이다(재확인:
# extract-checksum.sh SHA-256 yq_linux_<arch> 로 동일 값 산출 확인됨).
echo "Installing yq..."
YQ_VERSION="${YQ_VERSION:-v4.54.3}"
ARCH=$(dpkg --print-architecture)
case "$ARCH" in
  amd64) YQ_SHA256="${YQ_SHA256:-129534601871538efe0ba4c5e62a34fb1d5f469bcb975c4fddeb467d82974973}" ;;
  arm64) YQ_SHA256="${YQ_SHA256:-89f69310b61b68d1245065a1241d1fc843f7a36cd6103ffd77ad987613bd1b67}" ;;
  *) echo "No pinned yq checksum for architecture '$ARCH'; refusing to install unverified binary" >&2; exit 1 ;;
esac
fetch_release_asset mikefarah/yq "${YQ_VERSION}" "yq_linux_${ARCH}" /tmp/yq
echo "${YQ_SHA256}  /tmp/yq" | sha256sum -c -
install -m 755 /tmp/yq /usr/local/bin/yq
rm -f /tmp/yq
echo "  yq $(yq --version) installed"

# 성능 분석 도구
echo "Installing performance analysis tools..."
apt-get install -y \
  "linux-tools-$(uname -r)" 2>/dev/null || echo "Skipping linux-tools (kernel-specific)"

# eBPF 도구 (옵션)
echo "Installing eBPF tools (if available)..."
apt-get install -y \
  bpfcc-tools \
  bpftrace 2>/dev/null || echo "eBPF tools not available, skipping"

# auditd (CIS 벤치마크 대응 — 설치하되 기본 비활성화, EKS/GKE/AKS 노드 이미지 관행. I/O 오버헤드 방지 설정 포함)
echo "Installing auditd (installed but disabled by default)..."
apt-get install -y auditd
sed -i 's/^max_log_file = .*/max_log_file = 50/' /etc/audit/auditd.conf
sed -i 's/^max_log_file_action = .*/max_log_file_action = ROTATE/' /etc/audit/auditd.conf
sed -i 's/^disk_full_action = .*/disk_full_action = SUSPEND/' /etc/audit/auditd.conf
systemctl disable --now auditd 2>/dev/null || true
echo "  -> auditd installed but disabled (활성화: systemctl enable --now auditd)"

echo "=== 03-os-packages.sh: Complete ==="
