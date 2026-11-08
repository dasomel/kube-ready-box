#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
#
# prepare-image.sh 로 만든 qcow2 를 lima(vz)로 띄워 박스 검증과 단일 노드 kubeadm
# 클러스터 검증을 차례로 실행한다. verify_box.sh 의 RFP 원격 블록을 그대로 재사용한다.
# 사용: run.sh <qcow2>   (KEEP=1 이면 끝난 뒤 인스턴스를 남긴다)
set -euo pipefail

IMAGE="${1:?usage: run.sh <image.qcow2>}"
NAME="${LIMA_NAME:-krb-lima}"
CPUS="${LIMA_CPUS:-4}"
MEMORY="${LIMA_MEMORY:-6GiB}"
# D2: 현재 박스의 가상 디스크는 977GiB 이고 lima 는 디스크를 줄이지 못한다
# ("disk shrinking is not supported"). 박스 disk_size 를 줄이기 전까지 이 값이 필요하다.
DISK="${LIMA_DISK:-1000GiB}"
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"
KEEP="${KEEP:-0}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
[ -f "$IMAGE" ] || { echo "image not found: $IMAGE" >&2; exit 1; }
IMAGE="$(cd "$(dirname "$IMAGE")" && pwd)/$(basename "$IMAGE")"

# 남의 인스턴스를 지우지 않도록, 존재 확인을 trap 보다 먼저 하고 이 실행이 만든 것만 지운다.
if limactl list -q 2>/dev/null | grep -x "$NAME" >/dev/null; then
  echo "lima instance '$NAME' already exists; delete it or set LIMA_NAME" >&2
  exit 1
fi
work="$(mktemp -d)"
created=0
cleanup() {
  rm -rf "$work"
  if [ "$created" = 1 ] && [ "$KEEP" != "1" ]; then
    limactl delete -f "$NAME" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

cat > "$work/lima.yaml" <<EOF
vmType: vz
arch: aarch64
cpus: ${CPUS}
memory: ${MEMORY}
disk: ${DISK}
images:
  - location: "${IMAGE}"
    arch: aarch64
mounts: []
containerd:
  system: false
  user: false
EOF

start=$(date +%s)
created=1
limactl start --name="$NAME" --tty=false "$work/lima.yaml" > "$work/start.log" 2>&1 \
  || { tail -20 "$work/start.log" >&2; exit 1; }
echo "lima_ready PASS ($(( $(date +%s) - start ))s)"

g() { limactl shell "$NAME" "$@"; }
# 검사 스크립트는 판정을 출력할 뿐 실패로 끝나지 않으므로 여기서 게이트를 건다.
# UNKNOWN 은 PASS 가 아니지만 실행을 실패시키지도 않는다(docs/evidence-contracts.md).
preflight_gate() { # $1=STRICT_RUNTIME
  local last
  last="$(g sudo STRICT_RUNTIME="$1" /usr/local/bin/k8s-node-preflight text | tail -n1 || true)"
  echo "$last"
  case "$last" in failures=0\ *) ;; *) echo "preflight failed" >&2; exit 1 ;; esac
}
rfp_gate() { # $1=STRICT_RUNTIME
  local out
  out="$(g sudo STRICT_RUNTIME="$1" AIR_GAPPED=0 bash -s < "$work/rfp-remote.sh" || true)"
  printf '%s\n' "$out" | grep -v "$(printf '\tPASS\t')"
  printf '%s\n' "$out" | tail -n1 | grep '"status":"PASS"' >/dev/null || { echo "RFP profile failed" >&2; exit 1; }
}
awk "/<<'REMOTE'/{f=1;next} /^REMOTE\$/{f=0} f" "$repo/test-vm/verify_box.sh" > "$work/rfp-remote.sh"
[ -s "$work/rfp-remote.sh" ] || { echo "could not extract RFP block from verify_box.sh" >&2; exit 1; }

echo "=== box preflight (STRICT_RUNTIME=0) ==="
preflight_gate 0
echo "=== RFP profile (STRICT_RUNTIME=0) ==="
rfp_gate 0

echo "=== runtime install ==="
g sudo bash -s < "$here/guest/install-runtime.sh"
echo "=== preflight (STRICT_RUNTIME=1) ==="
preflight_gate 1

echo "=== kubeadm init ==="
g sudo kubeadm init --pod-network-cidr="$POD_CIDR" > "$work/kubeadm-init.log" 2>&1 \
  || { tail -30 "$work/kubeadm-init.log" >&2; exit 1; }
grep -E '^\[WARNING|initialized successfully' "$work/kubeadm-init.log" || true

echo "=== cluster check ==="
g bash -s < "$here/guest/cluster-check.sh"

echo "=== RFP profile (STRICT_RUNTIME=1) ==="
rfp_gate 1
echo "=== failed units ==="
g systemctl --failed --no-legend || true
