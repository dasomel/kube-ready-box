#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 dasomel
set -e

echo "=== 06-nic-tuning.sh: Network Interface Optimization ==="

# 메인 인터페이스 자동 감지
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

if [ -z "$INTERFACE" ]; then
  echo "WARNING: No default network interface found, skipping NIC tuning"
  exit 0
fi

echo "Optimizing network interface: $INTERFACE"

# Ring buffer 최대화
echo "Setting ring buffer sizes..."
ethtool -G "$INTERFACE" rx 4096 tx 4096 2>/dev/null || \
  echo "Ring buffer adjustment not supported (normal for virtual NICs)"

# Offloading 활성화
echo "Enabling offloading features..."
ethtool -K "$INTERFACE" tso on gso on gro on 2>/dev/null || \
  echo "Offloading features may not be fully supported"

# Interrupt coalescing
echo "Setting interrupt coalescing..."
ethtool -C "$INTERFACE" rx-usecs 50 tx-usecs 50 2>/dev/null || \
  echo "Interrupt coalescing not supported (normal for virtual NICs)"

echo ""
echo "Network interface $INTERFACE optimization attempted"
echo "Some features may not be supported on virtual NICs (this is normal)"
echo ""

echo "=== 06-nic-tuning.sh: Complete ==="
