#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 dasomel
set -e

echo "=== 04-k8s-prereq.sh: Kubernetes Prerequisites ==="

#=========================================
# K8s 필수 사전 조건 (런타임/컴포넌트 미포함)
#=========================================

# 스왑 비활성화 (K8s 필수)
# vm.swappiness는 02-os-tuning.sh에서 설정됨
echo "Disabling swap..."
swapoff -a
sed -i '/swap/d' /etc/fstab

# 필수 커널 모듈 로드
echo "Loading required kernel modules..."
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# 필수 네트워크 설정
echo "Configuring network settings for K8s..."
cat <<EOF > /etc/sysctl.d/k8s-network.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# IPv6 비활성화 (K8s 권장)
echo "Disabling IPv6..."
cat <<EOF > /etc/sysctl.d/k8s-disable-ipv6.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

sysctl --system

# K8s 설치에 필요한 기본 패키지
echo "Installing K8s required packages..."
apt-get update
apt-get install -y \
  socat \
  conntrack \
  ipset \
  ipvsadm \
  ebtables

# apt 키링 디렉토리 준비 (K8s 저장소 추가용)
echo "Preparing keyrings directory..."
mkdir -p /etc/apt/keyrings

echo ""
echo "=== K8s Prerequisites Configured ==="
echo "다음 단계에서 사용자가 직접 설치:"
echo "  1. 컨테이너 런타임 (containerd, CRI-O 등)"
echo "  2. kubeadm, kubelet, kubectl"
echo "  3. CNI 플러그인"
echo ""
echo "=== 04-k8s-prereq.sh: Complete ==="
