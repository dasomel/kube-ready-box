#!/bin/bash
set -euo pipefail

TARGET_PROVIDER="${1:-}"

echo "=== 검증 시작: $(date) ==="
if [ -n "$TARGET_PROVIDER" ]; then
  echo "Provider: ${TARGET_PROVIDER}"
fi
echo ""

vagrant ssh -c '
set -e
failures=0

pass() { echo "   [OK] $1"; }
fail() { echo "   [FAIL] $1"; failures=$((failures + 1)); }

echo ">>> 1. 운영체제 및 아키텍처 확인"
echo "   - OS Version: $(lsb_release -d | cut -f2)"
echo "   - Kernel: $(uname -r)"
echo "   - Arch: $(uname -m)"

echo ""
echo ">>> 2. 필수 패키지 설치 확인"
for pkg in curl git vim net-tools; do
  if dpkg-query -W -f="${Status}" "$pkg" 2>/dev/null | grep -q "install ok installed"; then
    pass "$pkg 설치됨"
  else
    fail "$pkg 설치 안됨"
  fi
done

echo ""
echo ">>> 3. 시스템 튜닝(K8s 요건) 확인"
if [ -z "$(swapon --show)" ]; then
  pass "Swap 비활성화됨"
else
  fail "Swap 활성화 상태 (K8s 설치 시 문제됨)"
  swapon --show
fi

ipv6_val=$(sysctl -n net.ipv6.conf.all.disable_ipv6)
if [ "$ipv6_val" = "1" ]; then
  pass "IPv6 비활성화됨"
else
  fail "IPv6 활성화됨 (값: $ipv6_val)"
fi

echo ""
echo ">>> 4. 커널 모듈 로드 확인"
for mod in br_netfilter overlay; do
  if lsmod | grep -q "^${mod}[[:space:]]"; then
    pass "모듈 ${mod} 로드됨"
  else
    fail "모듈 ${mod} 로드 안됨"
  fi
done

echo ""
echo ">>> 5. 디스크 및 메모리 확인"
df -h / | grep /
free -h | grep Mem

echo ""
if [ "$failures" -gt 0 ]; then
  echo ">>> RESULT: FAIL (${failures} issues)"
  exit 1
fi
echo ">>> RESULT: PASS"
'
