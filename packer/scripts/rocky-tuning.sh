#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 dasomel
set -e

echo "=== rocky-tuning.sh: Rocky Linux-specific Tuning ==="

ROCKY_VER="$(. /etc/os-release && echo "$VERSION_ID")"
KERNEL_VER="$(uname -r)"
echo "Detected Rocky Linux ${ROCKY_VER} (kernel ${KERNEL_VER})"

#=========================================
# SELinux: enforcing 강제 (config + runtime)
# rocky/preflight.sh의 selinux/selinux_config_consistency 체크가 PASS 되려면
# 둘 다 enforcing이어야 한다.
#=========================================
echo "Ensuring SELinux is enforcing..."
if [ -f /etc/selinux/config ]; then
  sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
  echo "  -> /etc/selinux/config set to SELINUX=enforcing"
fi
setenforce 1 2>/dev/null || echo "  -> setenforce 1 failed (build chroot/container may not support runtime SELinux; config is persisted)"
# 파일 라벨이 아직 맞지 않을 수 있으므로 다음 부팅 시 전체 재라벨링 안전망
touch /.autorelabel
echo "  -> /.autorelabel touched (full relabel on next boot)"

#=========================================
# firewalld: 설치 확인 + 활성화 + ssh 허용
#=========================================
echo "Configuring firewalld..."
if ! command -v firewall-cmd >/dev/null 2>&1; then
  dnf install -y firewalld
fi
systemctl enable --now firewalld
firewall-cmd --permanent --add-service=ssh
firewall-cmd --reload
echo "  -> firewalld active, ssh service allowed"

#=========================================
# NetworkManager: 활성화 보장
#=========================================
echo "Ensuring NetworkManager is active..."
systemctl enable --now NetworkManager

#=========================================
# iptables backend: nft로 등록 (rocky/preflight.sh의 iptables_backend 체크가
# update-alternatives 등록을 요구함)
#=========================================
echo "Installing iptables-nft..."
dnf install -y iptables-nft

#=========================================
# THP (투명 대용량 페이지) - K8s 워크로드에 따라 madvise 선택
#=========================================
echo "Configuring Transparent Huge Pages..."
if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
  echo 'madvise' > /sys/kernel/mm/transparent_hugepage/enabled
  echo 'madvise' > /sys/kernel/mm/transparent_hugepage/defrag
  echo "THP set to madvise mode"
fi

#=========================================
# systemd-oomd 비활성화 (K8s 자체 eviction 사용)
#=========================================
echo "Disabling systemd-oomd (K8s uses its own eviction)..."
systemctl disable --now systemd-oomd 2>/dev/null || \
  echo "systemd-oomd not found or already disabled"

#=========================================
# journald 로그 크기 제한 (디스크 절약)
#=========================================
echo "Configuring journald log limits..."
mkdir -p /etc/systemd/journald.conf.d
cat <<EOF > /etc/systemd/journald.conf.d/size-limit.conf
[Journal]
SystemMaxUse=500M
SystemKeepFree=1G
MaxRetentionSec=1week
EOF

systemctl restart systemd-journald

echo "=== rocky-tuning.sh: Complete ==="
