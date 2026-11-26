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
apt-get purge -y unattended-upgrades || true

# needrestart 제거 (Qualys 로컬 권한 상승 CVE 5건: CVE-2024-48990~48992, 2024-10224, 2024-11003)
# Ubuntu Server 기본 설치 패키지 - 공격 표면 축소 및 apt 인터랙티브 프롬프트 방지
echo "Removing needrestart (LPE CVEs, defense-in-depth)..."
apt-get purge -y needrestart || true

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
apt-get full-upgrade -y

# 보안 핵심 패키지 명시적 최신화 (CVE-2025-26465/26466 OpenSSH, CVE-2025-32462/32463 sudo, CVE-2026-23xxx 커널/AppArmor)
echo "Ensuring critical security packages are at latest version..."
apt-get install -y --only-upgrade \
  linux-image-generic \
  linux-headers-generic \
  linux-modules-extra-generic \
  apparmor \
  apparmor-utils \
  libapparmor1 \
  sudo \
  openssh-server \
  openssh-client \
  libssh-4 \
  libssl3t64 \
  || echo "  -> some packages were not present (skipped)"

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
  open-vm-tools \
  chrony

# 한국 NTP 서버 설정 (chrony — Ubuntu 25.10+/26.04 기본 데몬, K8s/etcd 권장. timesyncd 대체)
echo "Configuring Korean NTP servers (chrony)..."
mkdir -p /etc/chrony/sources.d
cat <<EOF > /etc/chrony/sources.d/kr-ntp.sources
server time.bora.net iburst
server time.kriss.re.kr iburst
server ntp.kornet.net iburst
server ntp.ubuntu.com iburst
EOF
systemctl disable --now systemd-timesyncd 2>/dev/null || true
systemctl enable chrony
chronyc reload sources || systemctl restart chrony || true
echo "  -> NTP servers: time.bora.net, time.kriss.re.kr, ntp.kornet.net, ntp.ubuntu.com"

# 불필요한 패키지 제거
echo "Cleaning up unnecessary packages..."
apt-get autoremove -y
apt-get clean

echo "=== 01-base.sh: Complete ==="
