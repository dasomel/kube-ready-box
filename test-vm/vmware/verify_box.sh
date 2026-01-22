#!/bin/bash
echo "=== 검증 시작: $(date) ==="

# Vagrant SSH를 통해 내부 명령 실행
vagrant ssh -c "
echo '>>> 1. 운영체제 및 아키텍처 확인'
echo '   - OS Version:' \$(lsb_release -d | cut -f2)
echo '   - Kernel:' \$(uname -r)
echo '   - Arch:' \$(uname -m)

echo -e '\n>>> 2. 필수 패키지 설치 확인'
PACKAGES='curl git vim net-tools'
for pkg in \$PACKAGES; do
  if dpkg -l | grep -q \$pkg; then
    echo \"   [OK] \$pkg 설치됨\"
  else
    echo \"   [FAIL] \$pkg 설치 안됨\"
  fi
done

echo -e '\n>>> 3. 시스템 튜닝(K8s 요건) 확인'
# Swap 확인
if [ -z \"\$(swapon --show)\" ]; then
  echo '   [OK] Swap 비활성화됨'
else
  echo '   [FAIL] Swap 활성화 상태 (K8s 설치 시 문제됨)'
  swapon --show
fi

# IPv6 확인
IPV6_VAL=\$(sysctl -n net.ipv6.conf.all.disable_ipv6)
if [ \"\$IPV6_VAL\" == \"1\" ]; then
  echo '   [OK] IPv6 비활성화됨'
else
  echo \"   [FAIL] IPv6 활성화됨 (값: \$IPV6_VAL)\"
fi

# 커널 모듈 확인
echo -e '\n>>> 4. 커널 모듈 로드 확인'
MODULES='br_netfilter overlay'
for mod in \$MODULES; do
  if lsmod | grep -q \$mod; then
    echo \"   [OK] 모듈 \$mod 로드됨\"
  else
    echo \"   [FAIL] 모듈 \$mod 로드 안됨\"
  fi
done

echo -e '\n>>> 5. 디스크 및 메모리 확인'
df -h / | grep /
free -h | grep Mem
"
