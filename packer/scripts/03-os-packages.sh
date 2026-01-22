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
  nethogs \
  dstat

# 네트워크 진단 도구
echo "Installing network diagnostic tools..."
apt-get install -y \
  ipvsadm \
  ipset \
  conntrack \
  ethtool \
  tcpdump \
  nmap

# 성능 분석 도구
echo "Installing performance analysis tools..."
apt-get install -y \
  linux-tools-$(uname -r) 2>/dev/null || echo "Skipping linux-tools (kernel-specific)"

# eBPF 도구 (옵션)
echo "Installing eBPF tools (if available)..."
apt-get install -y \
  bpfcc-tools \
  bpftrace 2>/dev/null || echo "eBPF tools not available, skipping"

echo "=== 03-os-packages.sh: Complete ==="
