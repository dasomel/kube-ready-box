#!/usr/bin/env bash
# #20 observability/node-diagnostic-profile.sh 한도/경계 테스트.
#
# 검증 대상: DIAGNOSTIC_DURATION_SECONDS (0..300, 숫자만), DIAGNOSTIC_MAX_BYTES
# (숫자만, 증거 크기 == 한도는 통과 / 한도+1 byte 초과는 거부), 수집기가 하나도
# 동작하지 않을 때의 UNKNOWN 보고(PASS 금지).
#
# 프로덕션 스크립트에는 증거 경로 override 를 두지 않는다(D7). 대신 스크립트의
# 임시 사본에서 리터럴 경로(/etc/os-release, /proc/..., /sys/class/net)와 도구 탐지
# (`command -v "$bin"`)를 sed 로 fixture 경로로 바꾸고, sleep/df/free/uname/
# dpkg-query 는 PATH 맨 앞의 stub 으로 대체한다. sleep stub 은 인자만 기록하므로
# DURATION=300 도 즉시 끝난다. 결과가 호스트(macOS/Linux)에 의존하지 않는다.
# python3 필요 (스크립트 자체가 python3에 의존).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/observability/node-diagnostic-profile.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

FIX="$WORKDIR/fix"
STUBBIN="$WORKDIR/bin"
mkdir -p "$FIX" "$STUBBIN"

# 스크립트 사본: 증거 소스 리터럴만 fixture 로 치환한다.
COPY="$WORKDIR/node-diagnostic-profile.sh"
sed \
  -e "s|/etc/os-release|$FIX/os-release|g" \
  -e "s|/proc/loadavg|$FIX/loadavg|g" \
  -e "s|/proc/net/dev|$FIX/netdev|g" \
  -e "s|/proc/sys/net/netfilter/nf_conntrack_count|$FIX/conntrack|g" \
  -e "s|/sys/class/net|$FIX/net|g" \
  -e "s|command -v \"\$bin\"|[ -e \"$FIX/tools/\$bin\" ]|" \
  "$SCRIPT" >"$COPY"
# 치환이 실제로 적용됐는지 확인 (무음 no-op 방지).
for needle in "$FIX/os-release" "$FIX/loadavg" "$FIX/netdev" "$FIX/conntrack" "$FIX/net" "$FIX/tools/"; do
  grep -qF "$needle" "$COPY" || { echo "FAIL: sed rewrite missing: $needle" >&2; exit 1; }
done

cat >"$STUBBIN/sleep" <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"$STUB_SLEEP_LOG"
STUB
cat >"$STUBBIN/uname" <<'STUB'
#!/usr/bin/env bash
echo x86_64
STUB
cat >"$STUBBIN/df" <<'STUB'
#!/usr/bin/env bash
[ -z "${STUB_DF_EMPTY:-}" ] || exit 0
echo "Filesystem 512-blocks Used Available Capacity Mounted"
case "$*" in
  *-Pi*) echo "/dev/x 1000 70 930 7% /" ;;
  *) echo "/dev/x 1000 500 500 50% /" ;;
esac
STUB
cat >"$STUBBIN/free" <<'STUB'
#!/usr/bin/env bash
[ -z "${STUB_FREE_EMPTY:-}" ] || exit 0
echo "              total        used        free      shared  buff/cache   available"
echo "Mem:           1000         400         100           0         500         600"
STUB
cat >"$STUBBIN/dpkg-query" <<'STUB'
#!/usr/bin/env bash
[ -z "${STUB_DPKG_EMPTY:-}" ] || exit 0
printf '1.2.3'
STUB
# python3 stub: 스크립트의 add() 는 체크마다 `python3 -c json.dumps` 를 한 번씩 띄워
# (실행당 ~27회, 호스트에 따라 수 초) 이 테스트의 실행 횟수에서는 너무 느리다.
# 그 정확히 한 가지 호출만 (따옴표/역슬래시 없는 fixture 문자열 한정) bash 로
# 대신하고, 그 외(집계 heredoc 등)는 실제 python3 로 그대로 넘긴다.
REAL_PY="$(command -v python3)"
cat >"$STUBBIN/python3" <<STUB
#!/usr/bin/env bash
if [ "\${1:-}" = -c ] && [ "\${2:-}" = 'import json,sys; print(json.dumps(sys.argv[1]))' ]; then
  printf '"%s"\\n' "\$3"
  exit 0
fi
exec "$REAL_PY" "\$@"
STUB
chmod +x "$STUBBIN"/*

reset_fixtures() { # 모든 수집기가 동작하는 기본 상태
  rm -rf "$FIX"
  mkdir -p "$FIX/net/lo" "$FIX/net/eth0" "$FIX/tools"
  echo 'ID="ubuntu"' >"$FIX/os-release"
  echo "0.52 0.40 0.30 1/100 1234" >"$FIX/loadavg"
  cat >"$FIX/netdev" <<'EOT'
Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo: 99999 5 9 9 0 0 0 0 99999 5 9 9 0 0 0 0
  eth0: 1000 10 1 2 0 0 0 0 2000 20 3 4 0 0 0 0
EOT
  echo 42 >"$FIX/conntrack"
}

OUT="$WORKDIR/out.json"
RC=0
run_script() { # 환경변수는 호출 측에서 env로 전달
  rm -f "$OUT" "$WORKDIR/sleep.log"
  : >"$WORKDIR/sleep.log"
  set +e
  PATH="$STUBBIN:$PATH" STUB_SLEEP_LOG="$WORKDIR/sleep.log" DIAGNOSTIC_OUTPUT="$OUT" \
    "$@" bash "$COPY" >"$WORKDIR/stdout.log" 2>"$WORKDIR/err.log"
  RC=$?
  set -e
}

jget() { # <check-id|-> <key>
  python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))
cid, key = sys.argv[2], sys.argv[3]
if cid == "-":
    print(d[key])
else:
    print(next(c[key] for c in d["checks"] if c["id"] == cid))
' "$OUT" "$1" "$2"
}

FAILED=0
expect() { # <label> <actual> <expected>
  if [ "$2" != "$3" ]; then
    echo "FAIL: $1: expected '$3', got '$2'" >&2
    FAILED=1
  fi
}
expect_contains() { # <label> <file> <substring>
  if ! grep -qF -- "$3" "$2"; then
    echo "FAIL: $1: '$3' not found in: $(cat "$2")" >&2
    FAILED=1
  fi
}
expect_no_output() { # <label> — 거부된 실행은 sleep 도, 증거 파일도 만들지 않는다
  expect "$1: no sleep" "$(wc -c <"$WORKDIR/sleep.log" | tr -d ' ')" 0
  expect "$1: no evidence file" "$([ -e "$OUT" ] && echo yes || echo no)" no
  # bash 의 `[ huge -le 300 ]` 는 "integer expression expected" 를 찍고 false 를 돌려줘
  # 한도 초과 메시지로 이어진다 (거부 동작은 정확하므로 그 한 가지 잡음만 허용).
  if grep -v 'integer expression expected' "$WORKDIR/err.log" | grep -qiE 'traceback|unbound variable|integer expression'; then
    echo "FAIL: $1: crash-style stderr: $(cat "$WORKDIR/err.log")" >&2
    FAILED=1
  fi
}

# 1. 기본 실행: 정상 스키마, 고정 raw_output, fixture 값이 그대로 반영된다.
reset_fixtures
run_script env DIAGNOSTIC_DURATION_SECONDS=1
expect "baseline rc" "$RC" 0
expect "baseline schema" "$(jget - schema)" kube-ready-observability/v1
expect "baseline kind" "$(jget - kind)" node-diagnostic
expect "baseline status" "$(jget - status)" PASS
expect "baseline raw_output" "$(jget - raw_output)" excluded-by-default
expect "baseline stdout==file" "$(cmp -s "$OUT" "$WORKDIR/stdout.log" && echo same || echo differ)" same
expect "baseline cpu" "$(jget cpu detail)" "load=0.52"
expect "baseline memory" "$(jget memory detail)" "used=400,available=600"
expect "baseline disk" "$(jget disk detail)" "used=50%"
expect "baseline inode" "$(jget inode detail)" "used=7%"
expect "baseline network_interfaces" "$(jget network_interfaces detail)" "count=2"
expect "baseline network_io (lo excluded)" "$(jget network_io detail)" \
  "rx_bytes=1000,rx_errors=1,rx_drop=2,tx_bytes=2000,tx_errors=3,tx_drop=4"
expect "baseline conntrack" "$(jget conntrack detail)" 42
expect "baseline os_id" "$(jget os_id detail)" ubuntu
expect "baseline tool absent" "$(jget tcpdump status)" UNKNOWN
expect "baseline tool absent detail" "$(jget tcpdump detail)" unavailable
expect "baseline sleep arg" "$(cat "$WORKDIR/sleep.log")" 1

# 2. 도구가 있으면 dpkg 버전으로 PASS, 버전을 못 얻으면 "available".
touch "$FIX/tools/tcpdump" "$FIX/tools/nmap"
run_script env DIAGNOSTIC_DURATION_SECONDS=1
expect "tool present status" "$(jget tcpdump status)" PASS
expect "tool present version" "$(jget tcpdump detail)" 1.2.3
run_script env DIAGNOSTIC_DURATION_SECONDS=1 STUB_DPKG_EMPTY=1
expect "tool present no-version" "$(jget nmap detail)" available
expect "tool still-absent stays UNKNOWN" "$(jget ethtool status)" UNKNOWN

# 3. DURATION 경계: 기본값 10, 0 / 300 은 통과 (sleep 인자로 확인).
reset_fixtures
run_script env
expect "default duration rc" "$RC" 0
expect "default duration sleep" "$(cat "$WORKDIR/sleep.log")" 10
run_script env DIAGNOSTIC_DURATION_SECONDS=
expect "empty duration falls back to default" "$(cat "$WORKDIR/sleep.log")" 10
run_script env DIAGNOSTIC_DURATION_SECONDS=0
expect "duration=0 rc" "$RC" 0
expect "duration=0 sleep" "$(cat "$WORKDIR/sleep.log")" 0
run_script env DIAGNOSTIC_DURATION_SECONDS=300
expect "duration=300 rc (at limit)" "$RC" 0
expect "duration=300 sleep" "$(cat "$WORKDIR/sleep.log")" 300
expect "duration=300 status" "$(jget - status)" PASS
run_script env DIAGNOSTIC_DURATION_SECONDS=0300
expect "duration=0300 rc (decimal, not octal)" "$RC" 0

# 4. DURATION 한도 초과는 거부(clamp 아님): 301, 매우 큰 값.
run_script env DIAGNOSTIC_DURATION_SECONDS=301
expect "duration=301 rc (just over)" "$RC" 2
expect_contains "duration=301 message" "$WORKDIR/err.log" "exceeds 300s"
expect_no_output "duration=301"
run_script env DIAGNOSTIC_DURATION_SECONDS=3600
expect "duration=3600 rc" "$RC" 2
expect_no_output "duration=3600"
run_script env DIAGNOSTIC_DURATION_SECONDS=99999999999999999999999
expect "duration=huge rc" "$RC" 2
expect_no_output "duration=huge"

# 5. DURATION 비숫자/잘못된 형식은 즉시 거부 (크래시 아님).
for bad in abc -1 1.5 1a "5 " " 5" 1e2 0x10 +5; do
  run_script env "DIAGNOSTIC_DURATION_SECONDS=$bad"
  expect "duration='$bad' rc" "$RC" 2
  expect_contains "duration='$bad' message" "$WORKDIR/err.log" "invalid DIAGNOSTIC_DURATION_SECONDS"
  expect_no_output "duration='$bad'"
done

# 6. MAX_BYTES 경계: 실제 증거 크기 S 를 측정해 S 는 통과, S-1 은 거부.
run_script env DIAGNOSTIC_DURATION_SECONDS=1
expect "size probe rc" "$RC" 0
SIZE=$(( $(wc -c <"$OUT") ))
[ "$SIZE" -gt 100 ] || { echo "FAIL: implausible evidence size $SIZE" >&2; FAILED=1; }
run_script env DIAGNOSTIC_DURATION_SECONDS=1 "DIAGNOSTIC_MAX_BYTES=$SIZE"
expect "max_bytes==size rc (at limit)" "$RC" 0
expect "max_bytes==size file bytes" "$(( $(wc -c <"$OUT") ))" "$SIZE"
run_script env DIAGNOSTIC_DURATION_SECONDS=1 "DIAGNOSTIC_MAX_BYTES=$((SIZE + 1))"
expect "max_bytes==size+1 rc" "$RC" 0
run_script env DIAGNOSTIC_DURATION_SECONDS=1 "DIAGNOSTIC_MAX_BYTES=$((SIZE - 1))"
expect "max_bytes==size-1 rc (just over)" "$RC" 1
expect_contains "max_bytes==size-1 message" "$WORKDIR/err.log" "exceeds configured bound $((SIZE - 1))"
expect "max_bytes==size-1 no truncated evidence" "$([ -e "$OUT" ] && echo yes || echo no)" no
expect "max_bytes==size-1 nothing on stdout" "$(wc -c <"$WORKDIR/stdout.log" | tr -d ' ')" 0
run_script env DIAGNOSTIC_DURATION_SECONDS=1 DIAGNOSTIC_MAX_BYTES=0
expect "max_bytes=0 rc" "$RC" 1
expect "max_bytes=0 no evidence" "$([ -e "$OUT" ] && echo yes || echo no)" no
run_script env DIAGNOSTIC_DURATION_SECONDS=1 DIAGNOSTIC_MAX_BYTES=
expect "empty max_bytes falls back to 10MiB default" "$RC" 0

# 7. MAX_BYTES 비숫자는 수집(sleep) 전에 거부 — traceback 으로 죽지 않는다.
for bad in abc -1 1.5 1e3 "10 " 0x10; do
  run_script env DIAGNOSTIC_DURATION_SECONDS=1 "DIAGNOSTIC_MAX_BYTES=$bad"
  expect "max_bytes='$bad' rc" "$RC" 2
  expect_contains "max_bytes='$bad' message" "$WORKDIR/err.log" "invalid DIAGNOSTIC_MAX_BYTES"
  expect_no_output "max_bytes='$bad'"
done

# 8. 수집기가 하나도 동작하지 않으면 PASS 가 아니라 UNKNOWN 이다.
rm -rf "$FIX"
mkdir -p "$FIX/tools"
run_script env DIAGNOSTIC_DURATION_SECONDS=1 STUB_DF_EMPTY=1 STUB_FREE_EMPTY=1
expect "no-collectors rc" "$RC" 0
expect "no-collectors overall status" "$(jget - status)" UNKNOWN
for id in cpu memory disk inode network_interfaces network_io conntrack os_id tcpdump; do
  expect "no-collectors $id status" "$(jget "$id" status)" UNKNOWN
  expect "no-collectors $id detail" "$(jget "$id" detail)" unavailable
done
# 정적 사실(profile/architecture)은 수집 성공의 근거가 아니다.
expect "no-collectors profile still static" "$(jget profile status)" PASS

# 9. 하나라도 실제로 측정되면 PASS (나머지 UNKNOWN 은 각자 UNKNOWN 으로 남는다).
echo "1.50 1 1 1/1 1" >"$FIX/loadavg"
run_script env DIAGNOSTIC_DURATION_SECONDS=1 STUB_DF_EMPTY=1 STUB_FREE_EMPTY=1
expect "one-collector overall status" "$(jget - status)" PASS
expect "one-collector cpu" "$(jget cpu detail)" "load=1.50"
expect "one-collector memory stays UNKNOWN" "$(jget memory status)" UNKNOWN

if [ "$FAILED" -ne 0 ]; then
  echo "node-diagnostic-profile-test: FAILED" >&2
  exit 1
fi
echo "node-diagnostic-profile-test: OK"
