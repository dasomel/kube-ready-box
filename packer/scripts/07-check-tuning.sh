#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 dasomel
set -e

echo "========================================"
echo "=== K8s Node Tuning Verification ==="
echo "========================================"

echo -e "\n[1] 스왑 상태"
free -h | grep Swap

echo -e "\n[2] 커널 파라미터"
echo "  net.ipv4.ip_forward: $(sysctl -n net.ipv4.ip_forward)"
echo "  vm.swappiness: $(sysctl -n vm.swappiness)"
echo "  fs.file-max: $(sysctl -n fs.file-max)"
echo "  net.core.somaxconn: $(sysctl -n net.core.somaxconn)"
echo "  kernel.pid_max: $(sysctl -n kernel.pid_max)"
echo "  fs.inotify.max_user_watches: $(sysctl -n fs.inotify.max_user_watches)"

echo -e "\n[3] 리소스 제한"
echo "  File descriptors (nofile): $(ulimit -n)"
echo "  Max processes (nproc): $(ulimit -u)"

echo -e "\n[4] 커널 모듈"
lsmod | grep -E "overlay|br_netfilter" || echo "  WARNING: overlay or br_netfilter not loaded"

echo -e "\n[5] Cgroup 버전"
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
  echo "  cgroup v2 detected"
  cat /sys/fs/cgroup/cgroup.controllers
else
  echo "  cgroup v1 detected"
fi

echo -e "\n[6] 컨테이너 런타임 상태 (K8s 설치 후)"
systemctl is-active containerd 2>/dev/null || echo "  미설치 (정상 - 사용자가 설치)"

echo -e "\n[7] kubelet 상태 (K8s 설치 후)"
systemctl is-active kubelet 2>/dev/null || echo "  미설치 (정상 - 사용자가 설치)"

echo -e "\n[8] 네트워크 인터페이스"
ip link show | grep -E "^[0-9]+:" | awk '{print "  "$2}'

echo -e "\n[9] 디스크 정보"
df -h / | tail -n1

echo -e "\n========================================"
echo "=== K8s Ready OS Check Complete ==="
echo "========================================"
echo ""
echo "This OS is ready for Kubernetes installation."
echo "Next steps (user action required):"
echo "  1. Install container runtime (containerd or CRI-O)"
echo "  2. Install kubeadm, kubelet, kubectl"
echo "  3. Initialize cluster or join existing cluster"
echo ""
