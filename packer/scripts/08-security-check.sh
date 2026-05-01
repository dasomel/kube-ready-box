#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 dasomel
# 보안 패치 검증 - 빌드 시점에 주요 CVE 영향 패키지의 버전을 기록
set -e

echo "=== 08-security-check.sh: Security Patch Verification ==="

LOG_PATH="/var/log/kube-ready-box-security.log"
{
  echo "Generated at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Kernel: $(uname -r)"
  echo ""
  echo "--- Critical Package Versions ---"
  for pkg in linux-image-generic apparmor sudo openssh-server openssh-client libssh-4 libssl3t64; do
    ver=$(dpkg-query -W -f='${Version}\n' "$pkg" 2>/dev/null || echo "not-installed")
    printf "%-28s %s\n" "$pkg" "$ver"
  done
  echo ""
  echo "--- Pending Security Updates ---"
  apt-get -s -o Debug::NoLocking=true upgrade 2>/dev/null \
    | grep -i security || echo "(none)"
  echo ""
  echo "--- AppArmor Status ---"
  aa-status --json 2>/dev/null | head -c 2000 || aa-status 2>/dev/null | head -20 || echo "aa-status unavailable"
} | tee "$LOG_PATH"

echo ""
echo "Security audit log written to: $LOG_PATH"
echo "=== 08-security-check.sh: Complete ==="
