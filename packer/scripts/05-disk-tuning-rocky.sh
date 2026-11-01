#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 dasomel
set -euo pipefail

echo "=== 05-disk-tuning-rocky.sh: Disk I/O Optimization ==="

# D5: 빌드 중 16 GiB 루트를 유지하고 첫 부팅에서 확장한다.
# 비용: 첫 부팅에 디스크 작업이 추가된다. 실패하면 unit을 남겨 재시도할 수 있다.
echo "Installing first-boot LVM growth service..."
mkdir -p /etc/lvm/archive /etc/lvm/backup
dnf install -y cloud-utils-growpart
install -d -m 0755 /usr/local/sbin /etc/systemd/system /etc/vagrant-box
cat > /usr/local/sbin/kube-ready-growroot <<'SCRIPT'
#!/bin/bash
set -euo pipefail

VG="rocky-vg"
LV="/dev/rocky-vg/rocky-lv"
EVIDENCE="/etc/vagrant-box/growroot.json"

# UNKNOWN은 검증 전 상태다. 오류가 나면 unit을 남겨 다음 부팅에 재시도한다.
install -d -m 0755 /etc/vagrant-box
printf '{"schema":"kube-ready-growroot/v1","status":"UNKNOWN"}\n' > "$EVIDENCE"
echo "Growing root LV $LV"

PV=$(pvs --noheadings -o pv_name --select "vg_name=$VG" | tr -d '[:space:]')
if [ -z "$PV" ] || [ ! -b "$PV" ]; then
  echo "LVM PV not found for $VG: $PV" >&2
  exit 1
fi
DISK_NAME=$(lsblk -dno PKNAME "$PV")
PART_NUM=$(cat "/sys/class/block/$(basename "$PV")/partition")
if [ -z "$DISK_NAME" ] || [ -z "$PART_NUM" ]; then
  echo "PV is not a disk partition: $PV" >&2
  exit 1
fi
DISK="/dev/$DISK_NAME"
echo "Growing partition $PART_NUM on $DISK"
if output=$(growpart "$DISK" "$PART_NUM" 2>&1); then
  echo "$output"
elif [[ "$output" == NOCHANGE:* ]]; then
  echo "$output"
else
  echo "$output" >&2
  exit 1
fi

pvresize "$PV"
FREE=$(vgs --noheadings -o vg_free_count "$VG" | tr -d '[:space:]')
if ! [[ "$FREE" =~ ^[0-9]+$ ]]; then
  echo "Cannot determine free extents in $VG: $FREE" >&2
  exit 1
fi
if [ "$FREE" -gt 0 ]; then
  lvextend -l +100%FREE "$LV"
fi

FSTYPE=$(blkid -o value -s TYPE "$LV")
case "$FSTYPE" in
  ext4) resize2fs "$LV" ;;
  xfs)
    # D6: 루트 마운트를 직접 지정해 LV 경로와 /dev/mapper 별칭 차이를 피한다.
    # 비용: 이 서비스는 루트 LV 전용이다. 다른 LV로 옮기면 마운트 검증을 추가한다.
    xfs_growfs /
    ;;
  *)
    echo "Unsupported root filesystem: $FSTYPE" >&2
    exit 1
    ;;
esac

FREE=$(vgs --noheadings -o vg_free_count "$VG" | tr -d '[:space:]')
if [ "$FREE" != 0 ]; then
  echo "VG still has free extents: $FREE" >&2
  exit 1
fi
BYTES=$(blockdev --getsize64 "$LV")
# 직접 실행하는 테스트에서는 unit이 없다. 실제 첫 부팅에서는 성공 후 제거한다.
if [ -f /etc/systemd/system/kube-ready-growroot.service ]; then
  systemctl disable kube-ready-growroot.service
  rm -f /etc/systemd/system/kube-ready-growroot.service
  systemctl daemon-reload
fi
printf '{"schema":"kube-ready-growroot/v1","status":"PASS","filesystem":"%s","lv_bytes":%s}\n' "$FSTYPE" "$BYTES" > "$EVIDENCE"
echo "Root growth complete: $LV ($BYTES bytes, $FSTYPE)"
SCRIPT
chmod 0755 /usr/local/sbin/kube-ready-growroot

cat > /etc/systemd/system/kube-ready-growroot.service <<'UNIT'
[Unit]
Description=Grow kube-ready-box root filesystem on first boot
After=local-fs.target
Before=multi-user.target ssh.service sshd.service containerd.service kubelet.service
ConditionPathExists=/usr/local/sbin/kube-ready-growroot

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/kube-ready-growroot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable kube-ready-growroot.service
echo "  -> First-boot LVM growth service installed"

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
# fstab 최적화 (noatime, prjquota)
#=========================================
ROOT_FSTYPE=$(blkid -o value -s TYPE /dev/rocky-vg/rocky-lv 2>/dev/null || echo "unknown")
echo "Root filesystem detected: $ROOT_FSTYPE"
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

# XFS: prjquota 설정 (K8s ephemeral storage quota 지원) - packer/scripts/05-disk-tuning.sh
# (Ubuntu)와 동일 의도. RHEL9는 BLS 기반 부트로더라 update-grub 대신 grubby로
# 모든 커널 엔트리에 일괄 반영한다 - /etc/default/grub sed 편집이 아님.
if [ "$ROOT_FSTYPE" = "xfs" ]; then
  echo "XFS detected: configuring prjquota for K8s ephemeral storage quota..."

  # 1. fstab에 prjquota 추가 (root xfs 마운트 라인)
  if grep -q "prjquota" /etc/fstab; then
    echo "  -> prjquota already in fstab"
  else
    if sed -i '/ \/ .*xfs/ s/defaults/defaults,prjquota/' /etc/fstab && grep -q "prjquota" /etc/fstab; then
      echo "  -> Added prjquota to fstab"
    else
      echo "  -> WARNING: Could not add prjquota to fstab (grubby rootflags will handle it)"
    fi
  fi

  # 2. grubby로 모든 BLS 커널 엔트리에 rootflags=prjquota 반영
  if grubby --info=ALL 2>/dev/null | grep -q "rootflags=prjquota"; then
    echo "  -> rootflags=prjquota already applied via grubby"
  else
    grubby --update-kernel=ALL --args="rootflags=prjquota"
    echo "  -> Added rootflags=prjquota via grubby"
  fi

  # 3. initramfs 재생성 (prjquota 마운트 옵션 반영)
  dracut -f --regenerate-all
  echo "  -> initramfs regenerated with prjquota"
fi

# 현재 마운트된 파일시스템에도 적용 (재부팅 없이)
echo "Remounting filesystems with noatime..."
if [ "$ROOT_FSTYPE" = "xfs" ]; then
  mount -o remount,noatime,nodiratime,prjquota / 2>/dev/null || \
    echo "Note: Root remount may require reboot to take full effect"
else
  mount -o remount,noatime,nodiratime / 2>/dev/null || \
    echo "Note: Root remount may require reboot to take full effect"
fi

echo ""
echo "Disk I/O optimization applied:"
echo "  - I/O scheduler: none (SSD optimized)"
echo "  - Read-ahead: 256KB"
echo "  - Mount options: noatime,nodiratime"
if [ "$ROOT_FSTYPE" = "xfs" ]; then
  echo "  - XFS prjquota: enabled (fstab + grubby rootflags + initramfs)"
fi
echo ""

echo "=== 05-disk-tuning-rocky.sh: Complete ==="
