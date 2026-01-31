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

# 한국 미러로 변경 (다운로드 속도 향상)
echo "Switching to Korean mirror for faster downloads..."
ARCH=$(dpkg --print-architecture)
if [ "$ARCH" = "arm64" ]; then
  # ARM64: ports.ubuntu.com -> kr.ports.ubuntu.com
  sed -i 's|ports.ubuntu.com|kr.ports.ubuntu.com|g' /etc/apt/sources.list.d/ubuntu.sources
  echo "  -> ARM64: Using kr.ports.ubuntu.com"
elif [ "$ARCH" = "amd64" ]; then
  # AMD64: archive.ubuntu.com -> kr.archive.ubuntu.com
  sed -i 's|archive.ubuntu.com|kr.archive.ubuntu.com|g' /etc/apt/sources.list.d/ubuntu.sources
  sed -i 's|security.ubuntu.com|kr.archive.ubuntu.com|g' /etc/apt/sources.list.d/ubuntu.sources
  echo "  -> AMD64: Using kr.archive.ubuntu.com"
fi

# 한국 시간대로 설정 (Asia/Seoul, KST UTC+9)
echo "Setting timezone to Asia/Seoul (KST)..."
timedatectl set-timezone Asia/Seoul
echo "  -> Timezone: $(timedatectl show --property=Timezone --value)"

# 한국 NTP 서버로 설정 (시간 동기화)
echo "Configuring Korean NTP servers..."
mkdir -p /etc/systemd/timesyncd.conf.d
cat <<EOF > /etc/systemd/timesyncd.conf.d/kr-ntp.conf
[Time]
NTP=time.bora.net time.kriss.re.kr ntp.kornet.net
FallbackNTP=ntp.ubuntu.com
EOF
systemctl restart systemd-timesyncd
echo "  -> NTP servers: time.bora.net, time.kriss.re.kr, ntp.kornet.net"

# 패키지 최신화
echo "Updating package lists..."
apt-get update

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
