#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 dasomel
set -e

echo "=== 04-k8s-prereq-rocky.sh: Kubernetes Prerequisites ==="

#=========================================
# K8s 필수 사전 조건 (런타임/컴포넌트 미포함)
#=========================================

# 스왑 비활성화 (K8s 필수)
# vm.swappiness는 rocky-tuning.sh에서 설정됨
echo "Disabling swap..."
swapoff -a
sed -i '/swap/d' /etc/fstab

# 필수 커널 모듈 로드
# nf_conntrack/dm_mod는 Ubuntu 쪽 04-k8s-prereq.sh엔 없는 요구사항이지만,
# rocky/preflight.sh 56-57행이 이 두 모듈을 FAIL 체크하므로 Rocky는 명시적으로
# 로드/등록한다.
echo "Loading required kernel modules..."
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
nf_conntrack
dm_mod
EOF

modprobe overlay
modprobe br_netfilter
modprobe nf_conntrack
modprobe dm_mod

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

# CSI 스토리지 전제조건 (Longhorn V1 엔진 하드 요구사항)
# Ubuntu의 open-iscsi 대응은 iscsi-initiator-utils. dmsetup 바이너리는
# 별도 패키지가 아니라 device-mapper 패키지가 제공한다(dnf list dmsetup은
# 실패함 - rockylinux:9 컨테이너에서 직접 확인).
echo "Installing CSI storage prerequisites..."
dnf install -y iscsi-initiator-utils cryptsetup device-mapper

# Longhorn: iscsid 시작 전에 iscsi_tcp 모듈 로드 필요
echo "Configuring iscsi_tcp kernel module..."
cat <<EOF > /etc/modules-load.d/iscsi.conf
iscsi_tcp
EOF
modprobe iscsi_tcp
# rocky/preflight.sh 63행 iscsid_active 체크를 PASS로 만들려면 활성화까지 필요
systemctl enable --now iscsid

# bpffs 영구 마운트 (Cilium eBPF 리소스 유지용, 선택적 - Cilium은 없으면 자동 마운트)
echo "Configuring persistent bpffs mount..."
if ! grep -q '/sys/fs/bpf' /etc/fstab; then
  echo 'bpffs /sys/fs/bpf bpf defaults 0 0' >> /etc/fstab
fi
mountpoint -q /sys/fs/bpf || mount /sys/fs/bpf

echo ""
echo "=== K8s Prerequisites Configured ==="
echo "  - Swap 비활성화, 커널 모듈(overlay/br_netfilter/nf_conntrack/dm_mod), 네트워크 sysctl"
echo "  - CSI 스토리지 전제조건 (iscsi-initiator-utils, cryptsetup, dmsetup, iscsi_tcp, iscsid)"
echo "  - bpffs 영구 마운트 (/sys/fs/bpf)"
echo "다음 단계에서 사용자가 직접 설치:"
echo "  1. 컨테이너 런타임 (containerd, CRI-O 등)"
echo "  2. kubeadm, kubelet, kubectl"
echo "  3. CNI 플러그인"
echo ""
echo "=== 04-k8s-prereq-rocky.sh: Complete ==="
