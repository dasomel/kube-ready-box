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
  sshpass

# yq (mikefarah/yq) - YAML processor for K8s manifests
echo "Installing yq..."
YQ_VERSION=$(curl -sL https://api.github.com/repos/mikefarah/yq/releases/latest | jq -r '.tag_name')
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

echo "=== 03-os-packages.sh: Complete ==="
