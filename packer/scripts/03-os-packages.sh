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

# dool (dstat replacement) - not in Ubuntu 24.04 repos, install from GitHub
echo "Installing dool (dstat replacement)..."
curl -sL "https://raw.githubusercontent.com/scottchiefbaker/dool/master/dool" -o /usr/local/bin/dool
chmod +x /usr/local/bin/dool
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
# YQ_VERSION 으로 고정하고, 필요 시 환경변수로 override 한다.
echo "Installing yq..."
YQ_VERSION="${YQ_VERSION:-v4.44.3}"
ARCH=$(dpkg --print-architecture)
curl -sL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${ARCH}" -o /usr/local/bin/yq
chmod +x /usr/local/bin/yq
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
