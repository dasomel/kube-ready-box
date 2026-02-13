#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 dasomel
set -e

export DEBIAN_FRONTEND=noninteractive

echo "Waiting for cloud-init to finish..."
cloud-init status --wait || true

# 자동 업데이트 먼저 비활성화 (잠금 방지)
echo "Disabling unattended-upgrades..."
systemctl stop unattended-upgrades || true
systemctl disable unattended-upgrades || true
apt-get remove -y unattended-upgrades || true

# universe 리포지토리 활성화 (iotop, iftop, nload, nethogs, dool 등)
# 모든 Components 라인에 universe 추가 (main + security 모두)
echo "Enabling universe repository..."
sed -i '/^Components:/ { /universe/! s/$/ universe/ }' /etc/apt/sources.list.d/ubuntu.sources
echo "  -> universe enabled on all repository entries"
cat /etc/apt/sources.list.d/ubuntu.sources | grep "^Components:"

# 한국 시간대로 설정 (Asia/Seoul, KST UTC+9)
echo "Setting timezone to Asia/Seoul (KST)..."
ln -sf /usr/share/zoneinfo/Asia/Seoul /etc/localtime
echo "Asia/Seoul" > /etc/timezone
echo "  -> Timezone: $(cat /etc/timezone)"

# 한국 NTP 서버로 설정 (시간 동기화)
echo "Configuring Korean NTP servers..."
mkdir -p /etc/systemd/timesyncd.conf.d
cat <<EOF > /etc/systemd/timesyncd.conf.d/kr-ntp.conf
[Time]
NTP=time.bora.net time.kriss.re.kr ntp.kornet.net
FallbackNTP=ntp.ubuntu.com
EOF
systemctl restart systemd-timesyncd || true
echo "  -> NTP servers: time.bora.net, time.kriss.re.kr, ntp.kornet.net"

# 패키지 최신화 (기본 미러로 먼저 실행하여 universe 포함 전체 인덱스 확보)
echo "Updating package lists..."
apt-get update

# 한국 미러로 변경 (다운로드 속도 향상, 후속 스크립트에서 사용)
# kr.archive.ubuntu.com은 GeoIP DNS 사용 - 해외에서 us.kr.archive.ubuntu.com으로
# 리다이렉트되어 noble/noble-updates/noble-backports 섹션 제공 불가
echo "Switching to Korean mirror for faster downloads..."
ARCH=$(dpkg --print-architecture)
if [ "$ARCH" = "arm64" ]; then
  sed -i 's|ports.ubuntu.com|kr.ports.ubuntu.com|g' /etc/apt/sources.list.d/ubuntu.sources
  apt-get update
  echo "  -> ARM64: Using kr.ports.ubuntu.com"
elif [ "$ARCH" = "amd64" ]; then
  SOURCES_BAK=$(cat /etc/apt/sources.list.d/ubuntu.sources)
  sed -i 's|archive.ubuntu.com|kr.archive.ubuntu.com|g' /etc/apt/sources.list.d/ubuntu.sources
  sed -i 's|security.ubuntu.com|kr.archive.ubuntu.com|g' /etc/apt/sources.list.d/ubuntu.sources
  # apt-get update exits 0 even with Err: entries, so check output
  APT_OUT=$(apt-get update 2>&1) || true
  if echo "$APT_OUT" | grep -q "^Err:"; then
    echo "  -> AMD64: Korean mirror failed (GeoIP redirect), reverting to default"
    echo "$SOURCES_BAK" > /etc/apt/sources.list.d/ubuntu.sources
    apt-get update
  else
    echo "  -> AMD64: Using kr.archive.ubuntu.com"
  fi
fi

echo "Upgrading packages..."
apt-get upgrade -y

# 필수 패키지 설치
echo "Installing essential packages..."
apt-get install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  software-properties-common \
  wget \
  vim \
  git \
  net-tools \
  rsync \
  open-vm-tools


# 불필요한 패키지 제거
echo "Cleaning up unnecessary packages..."
apt-get autoremove -y
apt-get clean

echo "=== 01-base.sh: Complete ==="
