#!/usr/bin/env bash
# #19 time/node-time-readiness.sh 결정적 fixture 테스트: chronyc를 PATH 맨 앞의
# stub으로 대체해 offset 파싱/부호, 예산(TIME_READINESS_MAX_OFFSET_SECONDS),
# source 개수, source 신선도(LastRx), 데몬 불가 시 현재 동작을 검증한다.
#
# 스크립트의 Linux 전용 읽기(/sys clocksource, timedatectl, /dev/ptp*,
# /etc/os-release)는 호스트에 따라 PASS/UNKNOWN이 갈리지만 FAIL을 만들지 않으므로
# (offset_budget/sources/source_freshness/synchronized와 전체 status만 단언)
# macOS와 Linux 모두에서 같은 결과가 나온다. 해당 체크는 단언하지 않는다.
# python3 필요 (스크립트 자체가 python3에 의존).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/time/node-time-readiness.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

STUBBIN="$WORKDIR/bin"
mkdir -p "$STUBBIN"

# stub chronyc: 시나리오 fixture를 환경변수 경로에서 읽어 그대로 출력한다.
cat >"$STUBBIN/chronyc" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  tracking)
    cat "$STUB_TRACKING"
    exit "${STUB_RC:-0}"
    ;;
  sources)
    # 실제 chronyc는 -v일 때만 앞에 범례를 추가로 출력한다.
    if [ "${2:-}" = "-v" ] || [ "${3:-}" = "-v" ]; then
      cat <<'LEGEND'

  .-- Source mode  '^' = server, '=' = peer, '#' = local clock.
 / .- Source state '*' = current best, '+' = combined, '-' = not combined,
| /             'x' = may be in error, '~' = too variable, '?' = unusable.
||                                                 .- xxxx [ yyyy ] +/- zzzz
LEGEND
    fi
    cat "$STUB_SOURCES"
    exit "${STUB_RC:-0}"
    ;;
  *) exit 2 ;;
esac
STUB
chmod +x "$STUBBIN/chronyc"

write_tracking() { # <direction-line> <leap>
  cat >"$WORKDIR/tracking" <<EOT
Reference ID    : A9FEA97B (169.254.169.123)
Stratum         : 4
Ref time (UTC)  : Sat Oct 31 12:00:00 2026
System time     : $1
Last offset     : +0.000000123 seconds
RMS offset      : 0.000001000 seconds
Frequency       : 10.000 ppm slow
Residual freq   : +0.000 ppm
Skew            : 0.050 ppm
Root delay      : 0.000500000 seconds
Root dispersion : 0.000200000 seconds
Update interval : 64.0 seconds
Leap status     : $2
EOT
}

write_sources() { # <lastrx> (빈 값이면 source 없음)
  {
    echo "MS Name/IP address         Stratum Poll Reach LastRx Last sample"
    echo "==============================================================================="
    if [ -n "${1:-}" ]; then
      printf '^* 169.254.169.123              3   6   377 %6s  +12us[  +15us] +/-   20ms\n' "$1"
    fi
  } >"$WORKDIR/sources"
}

OUT="$WORKDIR/out.json"
RC=0
run_script() { # 환경변수는 호출 측에서 env로 전달
  set +e
  PATH="$STUBBIN:$PATH" STUB_TRACKING="$WORKDIR/tracking" STUB_SOURCES="$WORKDIR/sources" \
    "$@" bash "$SCRIPT" >"$OUT" 2>"$WORKDIR/err.log"
  RC=$?
  set -e
}

# JSON에서 체크 필드 또는 전체 필드를 꺼낸다.
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

# 1. 동기화됨 + 예산 이내: +0.0001s fast -> offset_budget PASS
write_tracking "0.000100000 seconds fast of NTP time" "Normal"; write_sources "34"
run_script env
expect "in-sync synchronized" "$(jget synchronized status)" PASS
expect "in-sync offset_budget" "$(jget offset_budget status)" PASS
expect "in-sync detail" "$(jget offset_budget detail)" "offset=0.0001;budget=1.0"
expect "in-sync sources" "$(jget sources status)" PASS
expect "in-sync freshness" "$(jget source_freshness status)" PASS
expect "in-sync overall" "$(jget - status)" PASS
expect "in-sync rc" "$RC" 0

# 2. 2.5s slow -> 부호 규약: slow는 음수, 예산(1.0) 초과 -> FAIL
write_tracking "2.500000000 seconds slow of NTP time" "Normal"; write_sources "34"
run_script env
expect "slow offset" "$(jget offset detail)" "-2.5"
expect "slow offset_budget" "$(jget offset_budget status)" FAIL
expect "slow offset_budget detail" "$(jget offset_budget detail)" "offset=-2.5;budget=1.0"
expect "slow overall" "$(jget - status)" FAIL
expect "slow rc" "$RC" 1

# 3. 2.5s fast -> 양수 부호, 예산 초과 FAIL (절댓값 비교)
write_tracking "2.500000000 seconds fast of NTP time" "Normal"; write_sources "34"
run_script env
expect "fast offset" "$(jget offset detail)" "2.5"
expect "fast offset_budget" "$(jget offset_budget status)" FAIL

# 4. 예산을 5로 올리면 같은 2.5s slow가 PASS
write_tracking "2.500000000 seconds slow of NTP time" "Normal"; write_sources "34"
run_script env TIME_READINESS_MAX_OFFSET_SECONDS=5
expect "custom-budget offset_budget" "$(jget offset_budget status)" PASS
expect "custom-budget detail" "$(jget offset_budget detail)" "offset=-2.5;budget=5"
expect "custom-budget overall" "$(jget - status)" PASS

# 5. source 0개 -> sources FAIL, 전체 FAIL (freshness는 확인 불가이므로 UNKNOWN)
write_tracking "0.000100000 seconds fast of NTP time" "Normal"; write_sources ""
run_script env
expect "zero-sources sources" "$(jget sources status)" FAIL
expect "zero-sources freshness" "$(jget source_freshness status)" UNKNOWN
expect "zero-sources overall" "$(jget - status)" FAIL

# 6. LastRx가 한도(기본 3600s)를 넘으면 freshness FAIL: 2h = 7200s
write_tracking "0.000100000 seconds fast of NTP time" "Normal"; write_sources "2h"
run_script env
expect "stale freshness" "$(jget source_freshness status)" FAIL
expect "stale freshness detail" "$(jget source_freshness detail)" "age=7200;max=3600"
expect "stale overall" "$(jget - status)" FAIL

# 7. 같은 LastRx라도 한도를 올리면 PASS (한도 환경변수 존중)
run_script env TIME_READINESS_MAX_SOURCE_AGE_SECONDS=10000
expect "raised-age-limit freshness" "$(jget source_freshness status)" PASS

# 8. 한도 이내 LastRx(59m=3540s)는 PASS (경계 아래)
write_sources "59m"
run_script env
expect "fresh freshness" "$(jget source_freshness status)" PASS

# 9. Leap status가 Normal이 아니면 synchronized FAIL
write_tracking "0.000100000 seconds fast of NTP time" "Not synchronised"; write_sources "34"
run_script env
expect "unsynced synchronized" "$(jget synchronized status)" FAIL
expect "unsynced overall" "$(jget - status)" FAIL

# 10. 데몬 불가(chronyc 비정상 종료, 출력 없음/오류문만): 현재 동작을 고정한다.
#     현재는 synchronized FAIL("unsynchronized"), offset/offset_budget/freshness UNKNOWN,
#     sources FAIL이며 JSON은 정상 출력된다. UNKNOWN이 더 정확할 수 있으나 이 테스트는
#     스크립트를 바꾸지 않고 현재 동작만 단언한다.
echo "506 Cannot talk to daemon" >"$WORKDIR/tracking"; : >"$WORKDIR/sources"
run_script env STUB_RC=1
expect "unreachable synchronized" "$(jget synchronized status)" FAIL
expect "unreachable synchronized detail" "$(jget synchronized detail)" unsynchronized
expect "unreachable offset" "$(jget offset status)" UNKNOWN
expect "unreachable offset_budget" "$(jget offset_budget status)" UNKNOWN
expect "unreachable sources" "$(jget sources status)" FAIL
expect "unreachable freshness" "$(jget source_freshness status)" UNKNOWN
expect "unreachable overall" "$(jget - status)" FAIL
expect "unreachable rc" "$RC" 1

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
echo "node-time-readiness-test: all scenarios passed"
