#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
#
# Ubuntu Vagrant box(VirtualBox/VMware arm64) -> lima(vz)용 qcow2 변환 PoC.
# 박스는 cloud-init 이 꺼진 채 배포되므로(설치기가 남긴 마커와 datasource None),
# QEMU(hvf)로 한 번 부팅해 lima 가 쓰는 NoCloud datasource 로 바꾼 뒤 봉인한다.
# 사용: prepare-image.sh <box 파일> <출력 qcow2>
# 필요: qemu-img, qemu-system-aarch64(Homebrew), ~/.vagrant.d 의 insecure key.
set -euo pipefail

BOX="${1:?usage: prepare-image.sh <box> <out.qcow2>}"
OUT="${2:?usage: prepare-image.sh <box> <out.qcow2>}"
# 2222 는 Vagrant 기본 포워드다. 이미 쓰는 VM 이 있으면 그 VM 에 접속해 cloud-init 을 지우게 되므로
# 비어 있는 높은 포트를 고른다.
SSH_PORT="${SSH_PORT:-$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')}"
KEY="${VAGRANT_KEY:-$HOME/.vagrant.d/insecure_private_keys/vagrant.key.rsa}"
EFI_CODE="${EFI_CODE:-$(brew --prefix qemu 2>/dev/null || echo /opt/homebrew)/share/qemu/edk2-aarch64-code.fd}"

[ -f "$BOX" ] || { echo "box not found: $BOX" >&2; exit 1; }
[ -f "$KEY" ] || { echo "vagrant insecure key not found: $KEY" >&2; exit 1; }
[ -f "$EFI_CODE" ] || { echo "EFI firmware not found: $EFI_CODE" >&2; exit 1; }

work="$(mktemp -d)"
qemu_pid=""
# 실패한 실행이 반쯤 바뀐 qcow2 를 남기지 않도록 임시 이름에 쓰고 성공했을 때만 옮긴다.
tmp_out="${OUT}.partial"
cleanup() {
  [ -n "$qemu_pid" ] && kill "$qemu_pid" 2>/dev/null || true
  rm -rf "$work" "$tmp_out"
}
trap cleanup EXIT

tar -tf "$BOX" > "$work/members"
vmdk="$(grep -E '\.vmdk$' "$work/members" | sed -n 1p)"
[ -n "$vmdk" ] || { echo "no vmdk in $BOX" >&2; exit 1; }
tar -xf "$BOX" -C "$work" "$vmdk"
qemu-img convert -O qcow2 "$work/$vmdk" "$tmp_out"
rm -f "$work/$vmdk"
truncate -s 64m "$work/vars.fd"

qemu-system-aarch64 -machine virt,accel=hvf -cpu host -smp 2 -m 2048 \
  -drive "if=pflash,format=raw,readonly=on,file=$EFI_CODE" \
  -drive "if=pflash,format=raw,file=$work/vars.fd" \
  -drive "if=virtio,format=qcow2,file=$tmp_out" \
  -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22" -device virtio-net-pci,netdev=n0 \
  -display none -serial "file:$work/serial.log" &
qemu_pid=$!

gssh() {
  ssh -q -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=3 -i "$KEY" -p "$SSH_PORT" vagrant@127.0.0.1 "$@"
}
for _ in $(seq 1 60); do
  kill -0 "$qemu_pid" 2>/dev/null || { echo "qemu exited early (port ${SSH_PORT} in use?)" >&2; tail -20 "$work/serial.log" >&2 || true; exit 1; }
  gssh true 2>/dev/null && break
  sleep 3
done
gssh true || { echo "guest ssh did not come up" >&2; tail -20 "$work/serial.log" >&2; exit 1; }

# D1: 설치기 마커/설정만 지우고 NoCloud 를 우선한다. None 을 뒤에 두어 cidata 가 없는
# 하이퍼바이저에서도 부팅은 막히지 않는다. 비용: 이 이미지는 Vagrant 박스와 달리 매 첫 부팅에
# cloud-init 을 돈다. 되돌리기: /etc/cloud/cloud-init.disabled 를 다시 만들면 된다.
gssh 'set -e
sudo rm -f /etc/cloud/cloud-init.disabled \
  /etc/cloud/cloud.cfg.d/99-installer.cfg \
  /etc/cloud/cloud.cfg.d/00-subiquity-disable-cloudinit-networking.cfg
printf "datasource_list: [NoCloud, None]\n" | sudo tee /etc/cloud/cloud.cfg.d/90-lima-nocloud.cfg >/dev/null
sudo cloud-init clean --logs --machine-id --seed
sudo truncate -s0 /etc/machine-id
sudo sync
sudo systemctl poweroff' || true

for _ in $(seq 1 30); do
  kill -0 "$qemu_pid" 2>/dev/null || { qemu_pid=""; break; }
  sleep 2
done
[ -z "$qemu_pid" ] || { echo "guest did not power off" >&2; exit 1; }
mv "$tmp_out" "$OUT"
qemu-img info "$OUT" | grep -E 'virtual size|disk size'
echo "image ready: $OUT"
