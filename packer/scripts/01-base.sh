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
  net-tools


# 불필요한 패키지 제거
echo "Cleaning up unnecessary packages..."
apt-get autoremove -y
apt-get clean

echo "=== 01-base.sh: Complete ==="
