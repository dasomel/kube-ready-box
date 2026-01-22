#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 dasomel
set -e

echo "=== Final Cleanup for Vagrant Box ==="

# Clean apt cache
echo "Cleaning apt cache..."
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*

# Clear log files
echo "Clearing log files..."
find /var/log -type f -name "*.log" -exec truncate -s 0 {} \;
find /var/log -type f -name "*.gz" -delete
find /var/log -type f -name "*.1" -delete

# Clear temporary files
echo "Clearing temporary files..."
rm -rf /tmp/*
rm -rf /var/tmp/*

# Clear bash history
echo "Clearing bash history..."
unset HISTFILE
rm -f /root/.bash_history
rm -f /home/*/.bash_history

# SSH host keys - 유지 (삭제 시 첫 부팅에서 SSH 연결 불가)
# Ubuntu 24.04는 자동 재생성을 보장하지 않으므로 유지
echo "Keeping SSH host keys for immediate SSH access..."

# Clear machine-id (will be regenerated on first boot)
echo "Clearing machine-id..."
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id

# Zero out free space for better compression
echo "Zeroing free space (this may take a while)..."
dd if=/dev/zero of=/EMPTY bs=1M 2>/dev/null || true
rm -f /EMPTY

# Sync filesystem
sync

echo "=== Cleanup Complete ==="
