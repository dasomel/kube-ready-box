#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORKDIR=$(mktemp -d)
LOOP=""
VG="growroot_test_$$"

cleanup() {
  umount "$WORKDIR/mount" 2>/dev/null || true
  vgchange -an "$VG" >/dev/null 2>&1 || true
  vgremove -ff "$VG" >/dev/null 2>&1 || true
  if [ -n "$LOOP" ]; then
    losetup -d "$LOOP" 2>/dev/null || true
  fi
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

# D6: 실제 loop/LVM을 쓰고 XFS의 '/' 인자만 테스트 마운트로 연결한다.
# 비용: privileged Linux 컨테이너가 필요하다. VM 첫 부팅 검증으로 대체할 수 있다.
cat > "$WORKDIR/xfs_growfs" <<'SHIM'
#!/usr/bin/env bash
test "$1" = / || exit 1
exec /usr/sbin/xfs_growfs "$TEST_MOUNT"
SHIM
chmod +x "$WORKDIR/xfs_growfs"
mkdir "$WORKDIR/mount"

for filesystem in ext4 xfs; do
  truncate -s 2G "$WORKDIR/disk.img"
  parted -s "$WORKDIR/disk.img" mklabel gpt mkpart primary 1MiB 513MiB
  LOOP=$(losetup --find --show --partscan "$WORKDIR/disk.img")
  PV="${LOOP}p1"
  partx -a "$LOOP" 2>/dev/null || true
  if [ ! -b "$PV" ]; then
    IFS=: read -r major minor < "/sys/class/block/$(basename "$PV")/dev"
    mknod "$PV" b "$major" "$minor"
  fi
  pvcreate -ff -y "$PV" >/dev/null
  vgcreate "$VG" "$PV" >/dev/null
  lvcreate -Zn -Wn -L 384M -n root "$VG" >/dev/null
  IFS=: read -r major minor < <(dmsetup info -c --noheadings -o major,minor "$VG-root" | tr -d ' ')
  mkdir -p "/dev/$VG"
  mknod "/dev/$VG/root" b "$major" "$minor"
  LV="/dev/$VG/root"
  if [ "$filesystem" = xfs ]; then
    mkfs.xfs -f "$LV" >/dev/null
  else
    mkfs.ext4 -F "$LV" >/dev/null
  fi
  mount "$LV" "$WORKDIR/mount"
  initial_fs_bytes=$(df -B1 --output=size "$WORKDIR/mount" | tail -1 | tr -d ' ')

  for os in ubuntu rocky; do
    script="$ROOT/packer/scripts/05-disk-tuning.sh"
    [ "$os" = rocky ] && script="$ROOT/packer/scripts/05-disk-tuning-rocky.sh"
    awk '/^cat > \/usr\/local\/sbin\/kube-ready-growroot/{copy=1; next} copy && /^SCRIPT$/{exit} copy {print}' "$script" \
      | sed -e "s@VG=\"[^\"]*\"@VG=\"$VG\"@" \
            -e "s@LV=\"/dev/[^\"]*\"@LV=\"$LV\"@" \
            -e "s@EVIDENCE=\"[^\"]*\"@EVIDENCE=\"$WORKDIR/growroot.json\"@" \
      > "$WORKDIR/growroot.sh"
    chmod +x "$WORKDIR/growroot.sh"
    export TEST_MOUNT="$WORKDIR/mount"
    PATH="$WORKDIR:$PATH" bash "$WORKDIR/growroot.sh" >/dev/null
    first_bytes=$(blockdev --getsize64 "$LV")
    first_fs_bytes=$(df -B1 --output=size "$WORKDIR/mount" | tail -1 | tr -d ' ')
    test "$first_bytes" -gt 402653184
    test "$first_fs_bytes" -gt "$initial_fs_bytes"
    PATH="$WORKDIR:$PATH" bash "$WORKDIR/growroot.sh" >/dev/null
    test "$(blockdev --getsize64 "$LV")" = "$first_bytes"
    test "$(df -B1 --output=size "$WORKDIR/mount" | tail -1 | tr -d ' ')" = "$first_fs_bytes"
    grep -q '"status":"PASS"' "$WORKDIR/growroot.json"
    echo "$os $filesystem: first=$first_bytes second=$first_bytes PASS"
  done

  umount "$WORKDIR/mount"
  vgchange -an "$VG" >/dev/null
  vgremove -ff "$VG" >/dev/null
  losetup -d "$LOOP"
  rm -f "$PV" "/dev/$VG/root"
  rmdir "/dev/$VG" 2>/dev/null || true
  LOOP=""
  rm "$WORKDIR/disk.img" "$WORKDIR/growroot.json"
done

echo "growroot-loop: all scenarios passed"
