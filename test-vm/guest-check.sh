#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
#
# 부팅한 박스 "안에서" 도는 점검 하나. .github/workflows/build-amd64.yml 의 Boot test 와
# tools/release/verify-candidate.sh(arm64 후보 박스)가 같은 파일을 쓴다(mistakes-log #10:
# 두 경로가 따로 자라지 않게 한 곳에 둔다). 호스트에서는 vagrant upload 후 `bash` 로 실행한다.
#
# D1: Ubuntu 전용 점검(dpkg 커널 잔여물, cloud-init, 설치기 커널 인자)은 ID != ubuntu 면
#     건너뛴다(Rocky 는 dpkg/cloud-init 이 없다). 건너뛴 점검은 "SKIP" 줄로 남긴다.
# D2: pending_security 는 정보 출력이지 판정이 아니다. apt 캐시가 비어 있으면 0 이 나오므로
#     apt-get update 가 성공했을 때만 숫자를 찍고, 못 하면 UNKNOWN 이다(0 으로 위장하지 않는다).
#     escape hatch: 실패를 판정에 넣고 싶으면 호출 쪽이 이 줄을 파싱한다.
set -u
rc=0
os_id=unknown
[ -r /etc/os-release ] && os_id=$(. /etc/os-release; echo "${ID:-unknown}")

for _ in $(seq 1 90); do
  [ -e /etc/vagrant-box/growroot.json ] && [ "$(systemctl is-system-running)" != starting ] && break
  sleep 2
done
echo "os_id=$os_id"
echo "kernel=$(uname -r) state=$(systemctl is-system-running)"
echo "cmdline=$(cat /proc/cmdline)"
failed=$(systemctl --failed --no-legend | wc -l); echo "failed_units=$failed"
[ "$failed" -eq 0 ] || { systemctl --failed --no-legend; rc=1; }

# shellcheck disable=SC2116,SC2086 # 여러 항목을 한 줄로 합쳐 찍는다
mods=$(ls /lib/modules); echo "modules=$(echo $mods)"
[ "$mods" = "$(uname -r)" ] || { echo "extra /lib/modules entries"; rc=1; }
if [ "$os_id" = ubuntu ]; then
  if sudo grep -Eq 'ds=nocloud|[[:space:]]autoinstall([[:space:]]|$)' /proc/cmdline /etc/default/grub /boot/grub/grub.cfg; then
    echo "installer kernel args present"; rc=1
  fi

  rcpk=$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'linux-*' | awk '$1=="rc"{print $2}')
  [ -z "$rcpk" ] || { echo "rc kernel packages: $rcpk"; rc=1; }
  test -f /etc/cloud/cloud-init.disabled || { echo "cloud-init not disabled"; rc=1; }
else
  echo "SKIP ubuntu-only checks (dpkg/cloud-init/installer args) on os_id=$os_id"
fi

cat /etc/vagrant-box/growroot.json; echo
grep -q '"status":"PASS"' /etc/vagrant-box/growroot.json || { echo "growroot not PASS"; rc=1; }
[ -z "$(swapon --show)" ] || { echo "swap active"; rc=1; }
findmnt -no FSTYPE,OPTIONS /

# 정보 출력: 남아 있는 보안 패치 수와 핵심 패키지 버전(릴리스 증거에 같이 남긴다).
if [ "$os_id" = ubuntu ]; then
  if sudo timeout 120 apt-get update -qq >/dev/null 2>&1; then
    pending=$(apt list --upgradable 2>/dev/null | grep -c -- -security || true)
    echo "pending_security=$pending"
  else
    echo "pending_security=UNKNOWN(apt-get update failed)"
  fi
  echo "pkgs: $(dpkg-query -W -f='${Package}=${Version} ' libc6 openssl openssh-server)"
else
  echo "pending_security=UNKNOWN(not ubuntu: no apt)"
  echo "pkgs: $(rpm -q --qf '%{NAME}=%{VERSION}-%{RELEASE} ' glibc openssl openssh-server)"
fi
echo "kernel_version=$(uname -r)"
exit $rc
