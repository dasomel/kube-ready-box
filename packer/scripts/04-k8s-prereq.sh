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
# subiquity 설치기가 만든 swap 파일(약 4GB)은 swapoff/fstab 정리 후에도 남아
# 박스 크기만 키웠다. 다시 쓰이지 않으므로 지운다.
rm -f /swap.img

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

# AppArmor unconfined 프로파일 전환 제한 해제 (컨테이너 런타임 필수, mistakes-log #34)
# Ubuntu 26.04 apparmor 패키지는 /usr/lib/sysctl.d/10-apparmor.conf에서
# kernel.apparmor_restrict_unprivileged_unconfined=1을 켠다. runc는 root일 때
# `exec <profile>` 전환을 요청한 뒤 컨테이너 권한으로 내려가 CAP_MAC_OVERRIDE를 잃고,
# 커널은 exec 시점에 그 전환을 `<profile>//&unconfined` 스택으로 바꾼다
# (감사 로그: "change_profile unprivileged unconfined converted to stacking").
# containerd 기본 프로파일은 peer=<profile>로만 signal을 허용하므로 같은 컨테이너
# 안 프로세스끼리도 시그널이 거부된다(예: PostgreSQL "could not signal for checkpoint").
# 파일 이름 20-이 10-apparmor.conf보다 뒤에 적용된다. 키가 없는 커널에서는 건너뛴다.
if [ -e /proc/sys/kernel/apparmor_restrict_unprivileged_unconfined ]; then
  echo "Allowing AppArmor profile changes from unconfined (container runtime)..."
  cat <<EOF > /etc/sysctl.d/20-apparmor.conf
# kube-ready-box: runc 컨테이너 라벨이 //&unconfined로 스택되지 않게 한다.
kernel.apparmor_restrict_unprivileged_unconfined = 0
EOF
fi

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

# CSI 스토리지 전제조건 (Longhorn V1 엔진 하드 요구사항)
echo "Installing CSI storage prerequisites..."
apt-get install -y open-iscsi cryptsetup dmsetup

# Longhorn: iscsid 시작 전에 iscsi_tcp 모듈 로드 필요
echo "Configuring iscsi_tcp kernel module..."
cat <<EOF > /etc/modules-load.d/iscsi.conf
iscsi_tcp
EOF
modprobe iscsi_tcp
systemctl enable iscsid

# bpffs 영구 마운트 (Cilium eBPF 리소스 유지용, 선택적 — Cilium은 없으면 자동 마운트)
echo "Configuring persistent bpffs mount..."
if ! grep -q '/sys/fs/bpf' /etc/fstab; then
  echo 'bpffs /sys/fs/bpf bpf defaults 0 0' >> /etc/fstab
fi

# apt 키링 디렉토리 준비 (K8s 저장소 추가용)
echo "Preparing keyrings directory..."
mkdir -p /etc/apt/keyrings

echo ""
echo "=== K8s Prerequisites Configured ==="
echo "  - Swap 비활성화, 커널 모듈(overlay/br_netfilter), 네트워크 sysctl, AppArmor unconfined 전환 제한 해제"
echo "  - CSI 스토리지 전제조건 (open-iscsi, cryptsetup, dmsetup, iscsi_tcp)"
echo "  - bpffs 영구 마운트 (/sys/fs/bpf)"
echo "다음 단계에서 사용자가 직접 설치:"
echo "  1. 컨테이너 런타임 (containerd, CRI-O 등)"
echo "  2. kubeadm, kubelet, kubectl"
echo "  3. CNI 플러그인"
echo ""
echo "=== 04-k8s-prereq.sh: Complete ==="
