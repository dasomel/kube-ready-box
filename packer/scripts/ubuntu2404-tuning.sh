#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 dasomel
set -e

echo "=== ubuntu2404-tuning.sh: Ubuntu 24.04 Specific Tuning ==="

#=========================================
# Ubuntu 24.04 특화 최적화
#=========================================

# 커널 스케줄러 튜닝 (저지연 옵션)
echo "Configuring Ubuntu 24.04 low-latency kernel parameters..."
cat <<EOF > /etc/sysctl.d/99-ubuntu2404-tuning.conf
# 스케줄러 지연시간 최소화
kernel.sched_min_granularity_ns = 1000000
kernel.sched_wakeup_granularity_ns = 500000

# 투명 대용량 페이지 (THP) 설정
# K8s 워크로드에 따라 'madvise' 또는 'never' 선택
# 데이터베이스 워크로드: never 권장
EOF

# THP 설정 (메모리 집약적 워크로드)
echo "Configuring Transparent Huge Pages..."
if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
  echo 'madvise' > /sys/kernel/mm/transparent_hugepage/enabled
  echo 'madvise' > /sys/kernel/mm/transparent_hugepage/defrag
  echo "THP set to madvise mode"
fi

# systemd-oomd 비활성화 (K8s 자체 eviction 사용)
echo "Disabling systemd-oomd (K8s uses its own eviction)..."
systemctl disable --now systemd-oomd 2>/dev/null || \
  echo "systemd-oomd not found or already disabled"

# journald 로그 크기 제한 (디스크 절약)
echo "Configuring journald log limits..."
mkdir -p /etc/systemd/journald.conf.d
cat <<EOF > /etc/systemd/journald.conf.d/size-limit.conf
[Journal]
SystemMaxUse=500M
SystemKeepFree=1G
MaxRetentionSec=1week
EOF

systemctl restart systemd-journald

echo "=== ubuntu2404-tuning.sh: Complete ==="
