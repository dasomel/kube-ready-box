#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 dasomel
set -e

echo "=== 03-os-packages-rocky.sh: Install Recommended Packages ==="

# 성능/진단 도구 (EPEL 필요 - 01-base-rocky.sh에서 활성화됨)
echo "Installing essential system packages..."
dnf install -y \
  sysstat \
  iotop \
  iftop \
  nload \
  nethogs

# dool (dstat replacement): 업스트림이 .deb 릴리스만 제공(scottchiefbaker/dool)
# 하므로 rpm 계열에는 이식하지 않는다. EPEL의 dstat은 dool의 후속 fork가 아니라
# 별개 도구라 억지 대체하지 않음 - 공급망을 명확히 남기기 위해 미포함 처리.

# 네트워크 진단 도구 (Ubuntu의 conntrack은 Rocky/EPEL에서 conntrack-tools로 제공)
echo "Installing network diagnostic tools..."
dnf install -y \
  ipvsadm \
  ipset \
  conntrack-tools \
  ethtool \
  tcpdump \
  nmap

# K8s 에코시스템 도구 (Ubuntu의 nfs-common 대응은 nfs-utils)
echo "Installing Kubernetes ecosystem tools..."
dnf install -y \
  jq \
  bzip2 \
  tar \
  bash-completion \
  nfs-utils \
  sshpass

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

# yq (mikefarah/yq) - YAML processor for K8s manifests
# "latest" 는 빌드 시점마다 달라져 재현 가능한 빌드를 깨뜨린다(#30 공급망 고정).
# YQ_VERSION 으로 고정하고, 필요 시 환경변수로 override 한다. arm64 체크섬은
# Ubuntu용 03-os-packages.sh(및 docs/build-inputs.md)에 이미 검증되어 있는 값을
# 그대로 재사용한다 - yq 바이너리는 배포판 무관 정적 Go 바이너리라 같은
# YQ_VERSION이면 동일 아티팩트/체크섬이다.
echo "Installing yq..."
YQ_VERSION="${YQ_VERSION:-v4.54.3}"
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) YQ_ARCH=amd64; YQ_SHA256="${YQ_SHA256:-129534601871538efe0ba4c5e62a34fb1d5f469bcb975c4fddeb467d82974973}" ;;
  aarch64) YQ_ARCH=arm64; YQ_SHA256="${YQ_SHA256:-89f69310b61b68d1245065a1241d1fc843f7a36cd6103ffd77ad987613bd1b67}" ;;
  *) echo "No pinned yq checksum for architecture '$ARCH'; refusing to install unverified binary" >&2; exit 1 ;;
esac
fetch_release_asset mikefarah/yq "${YQ_VERSION}" "yq_linux_${YQ_ARCH}" /tmp/yq
echo "${YQ_SHA256}  /tmp/yq" | sha256sum -c -
install -m 755 /tmp/yq /usr/local/bin/yq
rm -f /tmp/yq
echo "  yq $(yq --version) installed"

# eBPF 도구 (EPEL 제공, 옵션)
echo "Installing eBPF tools (if available)..."
dnf install -y \
  bpftrace \
  bcc-tools 2>/dev/null || echo "eBPF tools not available, skipping"

# audit (CIS 벤치마크 대응 - 설치하되 기본 비활성화, Ubuntu auditd와 동일 관행)
echo "Installing audit (installed but disabled by default)..."
dnf install -y audit
sed -i 's/^max_log_file = .*/max_log_file = 50/' /etc/audit/auditd.conf
sed -i 's/^max_log_file_action = .*/max_log_file_action = ROTATE/' /etc/audit/auditd.conf
sed -i 's/^disk_full_action = .*/disk_full_action = SUSPEND/' /etc/audit/auditd.conf
systemctl disable --now auditd 2>/dev/null || true
echo "  -> audit installed but disabled (활성화: systemctl enable --now auditd)"

echo "=== 03-os-packages-rocky.sh: Complete ==="
