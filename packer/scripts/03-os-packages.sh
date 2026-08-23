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

# dool (dstat replacement) - not in Ubuntu 24.04 repos, install from a pinned
# GitHub release .deb (#30 공급망 고정). "master" 브랜치 raw 스크립트를 그대로
# curl|install 하던 이전 방식은 업스트림이 조용히 바뀌면 그대로 흘러들어오는
# floating dependency였다.
echo "Installing dool (dstat replacement)..."
DOOL_VERSION="${DOOL_VERSION:-1.3.8}"
DOOL_SHA256="${DOOL_SHA256:-818c833551b365a89f6ae29f07df5ea34588563e2eebaf3b2f93d64f6c9787fd}"
curl -sL "https://github.com/scottchiefbaker/dool/releases/download/v${DOOL_VERSION}/dool-${DOOL_VERSION}.deb" -o /tmp/dool.deb
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
YQ_VERSION="${YQ_VERSION:-v4.44.3}"
ARCH=$(dpkg --print-architecture)
case "$ARCH" in
  amd64) YQ_SHA256="${YQ_SHA256:-a2c097180dd884a8d50c956ee16a9cec070f30a7947cf4ebf87d5f36213e9ed7}" ;;
  arm64) YQ_SHA256="${YQ_SHA256:-0e7e1524f68d91b3ff9b089872d185940ab0fa020a5a9052046ef10547023156}" ;;
  *) echo "No pinned yq checksum for architecture '$ARCH'; refusing to install unverified binary" >&2; exit 1 ;;
esac
curl -sL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${ARCH}" -o /tmp/yq
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
