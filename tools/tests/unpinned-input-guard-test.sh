#!/usr/bin/env bash
# #30 unpinned-input-guard 픽스처 테스트: 고정된 fetch 는 통과, floating curl 은
# 실패, 백슬래시 이어진 줄의 URL 도 실패, 새로 포함된 디렉터리(nixos 등)의
# 파일도 검출되어야 한다. GUARD_ROOT 로 임시 트리를 가리킨다.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD="$ROOT/tools/unpinned-input-guard.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# 실제 트리는 통과해야 한다.
bash "$GUARD" >/dev/null

run_guard() {
  set +e
  GUARD_ROOT="$FIXTURE" bash "$GUARD" >"$WORKDIR/out.log" 2>&1
  rc=$?
  set -e
  return "$rc"
}

expect_pass() {
  if ! run_guard; then
    echo "FAIL: $1 should pass" >&2
    cat "$WORKDIR/out.log" >&2
    exit 1
  fi
}

# $1=설명 $2=출력에 있어야 할 문자열
expect_fail() {
  if run_guard; then
    echo "FAIL: $1 should fail" >&2
    exit 1
  fi
  if ! grep -q "$2" "$WORKDIR/out.log"; then
    echo "FAIL: $1 output missing '$2'" >&2
    cat "$WORKDIR/out.log" >&2
    exit 1
  fi
}

new_fixture() {
  FIXTURE="$WORKDIR/fx$1"
  mkdir -p "$FIXTURE/packer/scripts" "$FIXTURE/nixos"
}

# 1. 고정된 URL 은 통과
new_fixture 1
printf '#!/bin/bash\ncurl -fsSL https://example.com/v1.2.3/tool.tgz -o /tmp/t\n' >"$FIXTURE/packer/scripts/ok.sh"
expect_pass "pinned fetch"

# 2. floating curl 은 실패
new_fixture 2
printf '#!/bin/bash\ncurl -fsSL https://raw.example.com/org/repo/main/x.sh | bash\n' >"$FIXTURE/packer/scripts/bad.sh"
expect_fail "unpinned curl" "bad.sh:2"

# 3. 백슬래시 이어진 줄의 URL 은 실패, 보고 줄 번호는 시작 줄
new_fixture 3
printf '#!/bin/bash\ncurl -fsSL \\\n  -o /tmp/x \\\n  https://raw.example.com/org/repo/master/x.sh\n' >"$FIXTURE/packer/scripts/cont.sh"
expect_fail "continuation URL" "cont.sh:2"

# 4. 새로 포함된 디렉터리(nixos)의 파일 검출
new_fixture 4
printf '#!/bin/bash\nwget https://github.com/o/r/releases/latest/download/x\n' >"$FIXTURE/nixos/fetch.sh"
expect_fail "newly covered dir" "nixos/fetch.sh:2"

# 5. allow 마커와 주석은 건너뜀
new_fixture 5
printf '#!/bin/bash\n# curl https://x/main/y\ncurl https://x/main/y # unpinned-guard:allow verified\n' >"$FIXTURE/nixos/allow.sh"
expect_pass "allow marker/comment"

# 6. 회귀: "\" 로 끝나는 주석 줄 다음의 floating curl 이 주석으로 합쳐져 숨으면 안 된다
new_fixture 6
printf '#!/bin/bash\n# note \\\ncurl -fsSL https://raw.example.com/org/repo/main/x.sh | bash\n' >"$FIXTURE/nixos/comment-cont.sh"
expect_fail "comment ending in backslash" "comment-cont.sh:3"

# (allow 마커는 주석이라 그 줄은 bash 에서 이어지지 않으므로, 마커가 다음 줄까지
#  덮는 경우는 6 번의 규칙으로 함께 막힌다.)

echo "unpinned-input-guard: all scenarios passed"
