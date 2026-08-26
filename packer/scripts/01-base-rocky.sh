#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 dasomel
set -e

echo "=== 01-base-rocky.sh: Base System Setup ==="

# Rocky는 Kickstart 설치라 cloud-init이 없음 - Ubuntu의 cloud-init 대기 가드 불필요

# EPEL 활성화 (iotop/iftop/nload/nethogs/bpftrace 등 03-os-packages-rocky.sh 의존)
echo "Enabling EPEL repository..."
dnf install -y epel-release

# 한국 시간대로 설정 (Asia/Seoul, KST UTC+9)
echo "Setting timezone to Asia/Seoul (KST)..."
timedatectl set-timezone Asia/Seoul
echo "  -> Timezone: $(timedatectl show -p Timezone --value)"

# NTP: Rocky 기본 풀(rocky.pool.ntp.org, chronyd via Kickstart)을 그대로 유지한다.
# Ubuntu 스크립트는 한국 NTP 서버로 강제 교체하지만, Rocky는 vendor pool이
# geo-aware NTP Pool Project 기반이라 임의로 교체할 근거가 약하고, 이번 슬라이스는
# 최소 변경 원칙(§Context)을 따른다 - 필요해지면 별도 이슈로 다룬다.

# 패키지 최신화
echo "Updating packages..."
dnf -y update

# 필수 패키지 설치
echo "Installing essential packages..."
dnf install -y \
  curl \
  wget \
  vim \
  git \
  rsync \
  net-tools

# 불필요한 패키지 제거
echo "Cleaning up unnecessary packages..."
dnf -y autoremove || true
dnf clean all

echo "=== 01-base-rocky.sh: Complete ==="
