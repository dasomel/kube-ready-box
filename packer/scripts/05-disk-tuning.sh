#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 dasomel
set -euo pipefail

echo "=== 05-disk-tuning.sh: Disk I/O Optimization ==="

#=========================================
# LVM 자동 확장 서비스 설치
# Vagrantfile에서 디스크 크기를 늘리면 부팅 시 자동 확장
#=========================================
echo "Installing LVM auto-extend service..."

# LVM 디렉토리 생성
mkdir -p /etc/lvm/archive /etc/lvm/backup

# growpart 설치 (파티션 확장용)
apt-get install -y cloud-guest-utils

# 부팅 시 디스크 자동 확장 스크립트 (전체 체인: 파티션 → PV → LV → 파일시스템)
cat > /usr/local/bin/extend-lvm.sh << 'LVMSCRIPT'
#!/bin/bash
# Auto-extend disk: partition → PV → LV → filesystem
# Supports both SATA (sda) and NVMe (nvme0n1) disks
set -e

LOG_TAG="extend-lvm"

log() {
  logger -t "$LOG_TAG" "$1"
  echo "$1"
}

# Wait for devices to be ready
sleep 3

# Find the disk device and LVM partition
DISK=""
PART_NUM=""
PART_DEV=""

# Check for NVMe disk first (common on VMware ARM64)
if [ -b /dev/nvme0n1 ]; then
  DISK="/dev/nvme0n1"
  # Find LVM partition (usually partition 3 on Ubuntu autoinstall)
  for p in 3 2 1; do
    if [ -b "/dev/nvme0n1p${p}" ]; then
      if pvs "/dev/nvme0n1p${p}" &>/dev/null; then
        PART_NUM=$p
        PART_DEV="/dev/nvme0n1p${p}"
        break
      fi
    fi
  done
# Check for SATA/SCSI disk
elif [ -b /dev/sda ]; then
  DISK="/dev/sda"
  for p in 3 2 1; do
    if [ -b "/dev/sda${p}" ]; then
      if pvs "/dev/sda${p}" &>/dev/null; then
        PART_NUM=$p
        PART_DEV="/dev/sda${p}"
        break
      fi
    fi
  done
fi

if [ -z "$DISK" ] || [ -z "$PART_DEV" ]; then
  log "No suitable disk/partition found for extension"
  exit 0
fi

log "Disk: $DISK, LVM partition: $PART_DEV (partition $PART_NUM)"

# Step 1: Extend partition using growpart
log "Step 1: Extending partition $PART_NUM on $DISK..."
if growpart "$DISK" "$PART_NUM" 2>&1; then
  log "  -> Partition extended successfully"
else
  log "  -> Partition already at maximum size or growpart failed"
fi

# Step 2: Resize Physical Volume
log "Step 2: Resizing PV $PART_DEV..."
if pvresize "$PART_DEV" 2>&1; then
  log "  -> PV resized successfully"
else
  log "  -> PV resize failed or not needed"
fi

# Step 3: Extend Logical Volume
VG_FREE=$(vgs --noheadings -o vg_free --units g ubuntu-vg 2>/dev/null | tr -d ' g' | cut -d. -f1)
if [ -n "$VG_FREE" ] && [ "$VG_FREE" -gt 0 ]; then
  log "Step 3: Extending LV by ${VG_FREE}GB..."
  if lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv 2>&1; then
    log "  -> LV extended successfully"
  else
    log "  -> LV extend failed"
  fi
else
  log "Step 3: No free space in VG, skipping LV extension"
fi

# Step 4: Resize filesystem
log "Step 4: Resizing filesystem..."
if resize2fs /dev/ubuntu-vg/ubuntu-lv 2>&1; then
  log "  -> Filesystem resized successfully"
else
  log "  -> Filesystem resize failed or not needed"
fi

# Show final disk usage
log "Disk extension complete. Current usage:"
df -h / | logger -t "$LOG_TAG"
LVMSCRIPT
chmod +x /usr/local/bin/extend-lvm.sh

# systemd 서비스 생성
cat > /etc/systemd/system/extend-lvm.service << 'SVCFILE'
[Unit]
Description=Extend LVM to use full disk
After=local-fs.target
ConditionPathExists=/dev/ubuntu-vg/ubuntu-lv

[Service]
Type=oneshot
ExecStart=/usr/local/bin/extend-lvm.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVCFILE

systemctl daemon-reload
systemctl enable extend-lvm.service
echo "  -> LVM auto-extend service installed"

# I/O 스케줄러 설정 (SSD용 - none/noop)
echo "Setting I/O scheduler for SSD..."
for disk in /sys/block/sd*/queue/scheduler; do
  if [ -f "$disk" ]; then
    echo "none" > "$disk" 2>/dev/null || echo "noop" > "$disk" 2>/dev/null || true
    echo "Set scheduler for $disk"
  fi
done

for disk in /sys/block/nvme*/queue/scheduler; do
  if [ -f "$disk" ]; then
    echo "none" > "$disk" 2>/dev/null || true
    echo "Set scheduler for $disk"
  fi
done

# Read-ahead 설정 (256KB)
echo "Configuring read-ahead..."
for disk in /sys/block/sd*/queue/read_ahead_kb; do
  if [ -f "$disk" ]; then
    echo "256" > "$disk" 2>/dev/null || true
    echo "Set read-ahead for $disk"
  fi
done

for disk in /sys/block/nvme*/queue/read_ahead_kb; do
  if [ -f "$disk" ]; then
    echo "256" > "$disk" 2>/dev/null || true
    echo "Set read-ahead for $disk"
  fi
done

#=========================================
# fstab에 noatime, nodiratime 적용
#=========================================
echo "Applying noatime,nodiratime to /etc/fstab..."

# 백업 생성
cp /etc/fstab /etc/fstab.bak

# ext4/xfs 파일시스템에 noatime,nodiratime 추가
# 이미 noatime이 있으면 건너뜀
if grep -q "noatime" /etc/fstab; then
  echo "noatime already configured in fstab"
else
  # defaults를 defaults,noatime,nodiratime으로 변경
  sed -i 's/defaults/defaults,noatime,nodiratime/g' /etc/fstab

  # 변경 확인
  if grep -q "noatime" /etc/fstab; then
    echo "Successfully added noatime,nodiratime to fstab"
  else
    echo "WARNING: Could not add noatime to fstab automatically"
    echo "Please add manually: noatime,nodiratime"
  fi
fi

# 현재 마운트된 파일시스템에도 적용 (재부팅 없이)
echo "Remounting filesystems with noatime..."
mount -o remount,noatime,nodiratime / 2>/dev/null || \
  echo "Note: Root remount may require reboot to take full effect"

echo ""
echo "Disk I/O optimization applied:"
echo "  - I/O scheduler: none (SSD optimized)"
echo "  - Read-ahead: 256KB"
echo "  - Mount options: noatime,nodiratime"
echo ""

echo "=== 05-disk-tuning.sh: Complete ==="
