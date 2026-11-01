#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
#
# 박스 디스크 이미지(vmdk/qcow2/raw)에서 취약점 스캐너가 읽는 파일만 꺼낸다:
# os-release, 배포판 release 파일, dpkg status, rpmdb, 박스 manifest.
# 루트는 LVM 위의 ext4/xfs 다(16 GiB LV, D5). 읽기 전용으로만 마운트한다.
#
# usage: sudo tools/box-pkgdb-extract.sh <disk-image> <out-dir>
# 필요: qemu-img, sfdisk, losetup, lvm2, blkid, mount (Linux, root)
set -euo pipefail

disk=${1:?usage: box-pkgdb-extract.sh <disk-image> <out-dir>}
out=${2:?usage: box-pkgdb-extract.sh <disk-image> <out-dir>}
[ -f "$disk" ] || { echo "disk not found: $disk" >&2; exit 2; }

work=$(mktemp -d)
raw="$work/disk.raw"
mnt="$work/root"
loops=()
vgs_activated=()
mounted=""

cleanup() {
  [ -n "$mounted" ] && umount "$mnt" 2>/dev/null || true
  for vg in "${vgs_activated[@]}"; do vgchange -an "$vg" >/dev/null 2>&1 || true; done
  for l in "${loops[@]}"; do losetup -d "$l" 2>/dev/null || true; done
  rm -rf "$work"
}
trap cleanup EXIT

# raw 변환 결과는 sparse 라 디스크 가상 크기(1 TB)만큼 공간을 쓰지 않는다.
qemu-img convert -O raw "$disk" "$raw"

while read -r start size; do
  loops+=("$(losetup -f --show -r -o $((start * 512)) --sizelimit $((size * 512)) "$raw")")
done < <(sfdisk -d "$raw" | sed -n 's/.*start= *\([0-9]*\), size= *\([0-9]*\).*/\1 \2/p')
[ "${#loops[@]}" -gt 0 ] || { echo "no partitions in $disk" >&2; exit 2; }

# 이 loop 장치 위의 VG 만 활성화한다(러너/호스트의 다른 VG 는 건드리지 않음).
pvscan --cache >/dev/null 2>&1 || true
for l in "${loops[@]}"; do
  vg=$(pvs --noheadings -o vg_name "$l" 2>/dev/null | tr -d ' ' || true)
  if [ -n "$vg" ]; then
    vgchange -ay "$vg" >/dev/null
    # udev 없는 컨테이너에서는 /dev/<vg>/<lv> 노드가 생기지 않는다.
    vgmknodes "$vg" >/dev/null 2>&1 || true
    vgs_activated+=("$vg")
  fi
done

candidates=("${loops[@]}")
for vg in "${vgs_activated[@]}"; do
  while read -r lv; do candidates+=("$lv"); done < <(lvs --noheadings -o lv_path "$vg" | tr -d ' ')
done

mkdir -p "$mnt"
root=""
for c in "${candidates[@]}"; do
  fstype=$(blkid -o value -s TYPE "$c" 2>/dev/null || true)
  case "$fstype" in
    ext4) opts=ro,noload ;;
    xfs) opts=ro,norecovery ;;
    *) continue ;;
  esac
  mount -o "$opts" "$c" "$mnt" 2>/dev/null || continue
  mounted=1
  if [ -d "$mnt/etc" ] && [ -d "$mnt/var/lib" ]; then root=$c; break; fi
  umount "$mnt"; mounted=""
done
[ -n "$root" ] || { echo "root filesystem not found in $disk" >&2; exit 2; }

mkdir -p "$out"
copied=0
for p in etc/os-release usr/lib/os-release etc/lsb-release etc/redhat-release etc/rocky-release \
         etc/system-release var/lib/dpkg/status var/lib/rpm/rpmdb.sqlite etc/vagrant-box/manifest.json; do
  if [ -e "$mnt/$p" ]; then
    mkdir -p "$out/$(dirname "$p")"
    cp -L "$mnt/$p" "$out/$p"
    copied=$((copied + 1))
  fi
done
if [ ! -e "$out/var/lib/dpkg/status" ] && [ ! -e "$out/var/lib/rpm/rpmdb.sqlite" ]; then
  echo "no dpkg/rpm database in $disk" >&2
  exit 2
fi
kernels=$(for k in "$mnt"/lib/modules/* "$mnt"/usr/lib/modules/*; do
  [ -d "$k" ] && basename "$k"
done | sort -u | tr '\n' ' ')
echo "root=$root files=$copied kernels=${kernels% }"
