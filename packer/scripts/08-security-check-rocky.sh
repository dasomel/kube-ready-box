#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 dasomel
# 보안 패치 검증 - 빌드 시점에 주요 CVE 영향 패키지의 버전을 기록
set -e

echo "=== 08-security-check-rocky.sh: Security Patch Verification ==="

LOG_PATH="/var/log/kube-ready-box-security.log"
{
  echo "Generated at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Kernel: $(uname -r)"
  echo ""
  echo "--- Critical Package Versions ---"
  for pkg in kernel openssh-server openssh-clients sudo openssl-libs glibc; do
    ver=$(rpm -q --qf '%{VERSION}-%{RELEASE}\n' "$pkg" 2>/dev/null || echo "not-installed")
    printf "%-28s %s\n" "$pkg" "$ver"
  done
  echo ""
  echo "--- Pending Security Updates ---"
  dnf updateinfo list security 2>/dev/null || echo "(none)"
  echo ""
  echo "--- SELinux Status ---"
  sestatus 2>/dev/null || getenforce 2>/dev/null || echo "SELinux status unavailable"
} | tee "$LOG_PATH"

echo ""
echo "Security audit log written to: $LOG_PATH"
echo "=== 08-security-check-rocky.sh: Complete ==="
