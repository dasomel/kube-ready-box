#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 dasomel
set -e

echo "=== ubuntu-tuning.sh: Ubuntu Version-specific Tuning ==="

# 실행 중인 Ubuntu 버전 감지 (24.04 / 26.04 ...)
UBUNTU_VER="$(. /etc/os-release && echo "$VERSION_ID")"
KERNEL_VER="$(uname -r)"
echo "Detected Ubuntu ${UBUNTU_VER} (kernel ${KERNEL_VER})"

#=========================================
# Ubuntu 버전 공통 최적화
#=========================================

# 스케줄러 튜닝 참고:
#   기존 CFS 튜너블 kernel.sched_min_granularity_ns / sched_wakeup_granularity_ns 는
#   커널 6.6에서 EEVDF 스케줄러로 교체되며 /proc/sys(sysctl)에서 debugfs로 이동되어
#   더 이상 sysctl.d 로 설정 불가(24.04=6.8, 26.04=7.0 모두 해당). 따라서 제거함.
#   EEVDF 등가 노브는 /sys/kernel/debug/sched/base_slice_ns (비영속, 고급 튜닝)이며
#   기본값 사용을 권장하므로 별도 설정하지 않음.

# THP (투명 대용량 페이지) - 메모리 집약적 워크로드
# K8s 워크로드에 따라 madvise/never 선택 (DB 워크로드는 never 권장)
echo "Configuring Transparent Huge Pages..."
if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
  echo 'madvise' > /sys/kernel/mm/transparent_hugepage/enabled
  echo 'madvise' > /sys/kernel/mm/transparent_hugepage/defrag
  echo "THP set to madvise mode"
fi

# systemd-oomd 비활성화 (K8s 자체 eviction 사용) - systemd 255/259 공통
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

#=========================================
# 버전별 분기 (향후 26 전용 튜닝 확장 지점)
#=========================================
case "$UBUNTU_VER" in
  26.04)
    # 26.04 = 커널 7.0 / systemd 259 / cgroup v2 전용.
    # cgroup 마운트 하드닝(nsdelegate, memory_recursiveprot 등)은 26.04 기본 제공 → 별도 설정 불필요.
    echo "Ubuntu 26.04: kernel 7.0 / cgroup v2-only defaults — no extra tuning needed"
    ;;
  24.04)
    echo "Ubuntu 24.04: baseline tuning applied"
    ;;
  *)
    echo "Ubuntu ${UBUNTU_VER}: applying common tuning only"
    ;;
esac

echo "=== ubuntu-tuning.sh: Complete ==="
