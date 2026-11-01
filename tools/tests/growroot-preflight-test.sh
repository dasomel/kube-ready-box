#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

# 실제 생성되는 preflight 분기를 추출하고 증거 경로만 테스트 파일로 바꾼다.
awk '/^# D6: 완료 증거/{copy=1} copy {print; if ($0 == "fi") exit}' \
  "$ROOT/packer/scripts/07-check-tuning.sh" \
  | sed "s@/etc/vagrant-box/growroot.json@$WORKDIR/growroot.json@g" > "$WORKDIR/check.sh"
test -s "$WORKDIR/check.sh"

systemctl() {
  if [ "$1" = is-enabled ]; then
    [ "${UNIT_ENABLED:-0}" = 1 ]
  elif [ "$1" = is-active ]; then
    [ "${UNIT_ACTIVE:-0}" = 1 ]
  else
    return 1
  fi
}

record() { printf '%s\t%s\n' "$1" "$2" > "$WORKDIR/result"; }

check() {
  local expected="$1"
  . "$WORKDIR/check.sh"
  if [ "$(cat "$WORKDIR/result")" != "$(printf 'lvm_auto_extend\t%s' "$expected")" ]; then
    echo "FAIL: expected $expected, got $(cat "$WORKDIR/result")" >&2
    exit 1
  fi
}

UNIT_ENABLED=1
UNIT_ACTIVE=0
check PASS
printf '{"status":"PASS"}\n' > "$WORKDIR/growroot.json"
UNIT_ENABLED=0
check PASS
printf '{"status":"UNKNOWN"}\n' > "$WORKDIR/growroot.json"
UNIT_ENABLED=1
check UNKNOWN
rm "$WORKDIR/growroot.json"
UNIT_ENABLED=0
check UNKNOWN

echo "growroot-preflight: all scenarios passed"
