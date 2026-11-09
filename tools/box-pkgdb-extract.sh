#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
#
# 박스 디스크 이미지(vmdk/qcow2/raw)에서 취약점 스캐너가 읽는 파일만 꺼낸다:
# os-release, 배포판 release 파일, dpkg status, rpmdb, 박스 manifest, 그리고
# 패키지 관리자 밖에서 설치한 독립 실행 파일(아래 allowlist; Trivy 가 Go 바이너리의
# 모듈/stdlib 버전을 읽는다). <out-dir>/.scanned-binaries 에 복사한 경로를 한 줄씩 남긴다.
# 루트는 LVM 위의 ext4/xfs 다(16 GiB LV, D5). 읽기 전용으로만 마운트한다.
#
# usage: sudo tools/box-pkgdb-extract.sh <disk-image> <out-dir>
# 필요: qemu-img, sfdisk, losetup, lvm2, blkid, mount (Linux, root)
set -euo pipefail

disk=${1:?usage: box-pkgdb-extract.sh <disk-image> <out-dir>}
out=${2:?usage: box-pkgdb-extract.sh <disk-image> <out-dir>}
[ -f "$disk" ] || { echo "disk not found: $disk" >&2; exit 2; }
# 이전 실행의 패키지 DB 가 남아 있으면 새 이미지에서 못 꺼낸 것을 성공으로 오인한다
# (UNKNOWN -> PASS). 비어 있지 않은 출력 디렉터리는 거부한다.
if [ -e "$out" ] && [ -n "$(ls -A "$out" 2>/dev/null)" ]; then
  echo "output dir not empty: $out" >&2; exit 2
fi
# 모든 Ubuntu 박스의 VG 는 ubuntu-vg, Rocky 는 rocky-vg 다. 같은 호스트에서 동시에
# 두 박스를 열면 VG 이름이 겹치므로 한 번에 하나만 처리한다.
exec 9>/run/lock/box-pkgdb-extract.lock 2>/dev/null || exec 9>/tmp/box-pkgdb-extract.lock
flock -w 1800 9 || { echo "another extraction holds the lock" >&2; exit 2; }

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
    # 같은 이름의 VG 가 호스트에 이미 있으면(박스 밖의 PV 가 섞이면) 손대지 않는다.
    for pv in $(pvs --noheadings -o pv_name -S "vg_name=$vg" 2>/dev/null); do
      case " ${loops[*]} " in
        *" $pv "*) ;;
        *) echo "VG $vg also exists outside this image ($pv); refusing to activate" >&2; exit 2 ;;
      esac
    done
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
# 독립 실행 파일 allowlist (/usr/local 재귀 복사 금지). 출처:
#   usr/local/bin/yq                         packer/scripts/03-os-packages.sh:110, 03-os-packages-rocky.sh:99
#   usr/local/bin/runsc                      packer/scripts/10-sandbox-runtime.sh:146
#   usr/local/bin/containerd-shim-runsc-v1   packer/scripts/10-sandbox-runtime.sh:147
#   usr/local/bin/gvisor-bin/*               packer/scripts/10-sandbox-runtime.sh:148-150 (helper 이름은 릴리스마다 달라 glob)
# dool 은 .deb(03-os-packages.sh:70 dpkg -i)라 dpkg status 로 이미 보인다. 나머지 /usr/local/{bin,sbin}
# 파일(k8s-node-preflight, kube-ready-*)은 셸 스크립트라 대상이 아니다.
# 없는 파일은 건너뛴다(gVisor 는 SANDBOX_PROFILE=1 박스에만 있다). 심볼릭 링크는 호스트 경로로
# 풀릴 수 있으므로 일반 파일만 복사한다.
: > "$out/.scanned-binaries"
bins=0
for p in usr/local/bin/yq usr/local/bin/runsc usr/local/bin/containerd-shim-runsc-v1 \
         "$mnt"/usr/local/bin/gvisor-bin/*; do
  p=${p#"$mnt"/}
  if [ -f "$mnt/$p" ] && [ ! -L "$mnt/$p" ]; then
    mkdir -p "$out/$(dirname "$p")"
    cp --preserve=mode "$mnt/$p" "$out/$p"
    echo "$p" >> "$out/.scanned-binaries"
    bins=$((bins + 1))
  fi
done
if [ ! -e "$out/var/lib/dpkg/status" ] && [ ! -e "$out/var/lib/rpm/rpmdb.sqlite" ]; then
  echo "no dpkg/rpm database in $disk" >&2
  exit 2
fi
kernels=$(for k in "$mnt"/lib/modules/* "$mnt"/usr/lib/modules/*; do
  [ -d "$k" ] && basename "$k"
done | sort -u | tr '\n' ' ')
echo "root=$root files=$copied binaries=$bins kernels=${kernels% }"
