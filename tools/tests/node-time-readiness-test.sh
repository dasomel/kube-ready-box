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
    match = next((c for c in d["checks"] if c["id"] == cid), None)
    print(match[key] if match else "")
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

# 10.1. offset 수치 임계치 경계(정확히 1.0s, 초과 1.000001s, 음수 절댓값 처리)
# - 정확히 양수 임계치(+1.0s fast): PASS
write_tracking "1.000000000 seconds fast of NTP time" "Normal"; write_sources "34"
run_script env
expect "exact-threshold-fast offset" "$(jget offset detail)" "1.0"
expect "exact-threshold-fast offset_budget" "$(jget offset_budget status)" PASS
expect "exact-threshold-fast offset_budget detail" "$(jget offset_budget detail)" "offset=1.0;budget=1.0"
expect "exact-threshold-fast overall" "$(jget - status)" PASS
expect "exact-threshold-fast rc" "$RC" 0

# - 양수 임계치 직전 초과(+1.000001s fast): FAIL
write_tracking "1.000001000 seconds fast of NTP time" "Normal"; write_sources "34"
run_script env
expect "just-over-fast offset" "$(jget offset detail)" "1.000001"
expect "just-over-fast offset_budget" "$(jget offset_budget status)" FAIL
expect "just-over-fast offset_budget detail" "$(jget offset_budget detail)" "offset=1.000001;budget=1.0"
expect "just-over-fast overall" "$(jget - status)" FAIL
expect "just-over-fast rc" "$RC" 1

# - 정확히 음수 임계치(-1.0s slow): 절댓값 비교로 PASS
write_tracking "1.000000000 seconds slow of NTP time" "Normal"; write_sources "34"
run_script env
expect "exact-threshold-slow offset" "$(jget offset detail)" "-1.0"
expect "exact-threshold-slow offset_budget" "$(jget offset_budget status)" PASS
expect "exact-threshold-slow offset_budget detail" "$(jget offset_budget detail)" "offset=-1.0;budget=1.0"
expect "exact-threshold-slow overall" "$(jget - status)" PASS
expect "exact-threshold-slow rc" "$RC" 0

# - 음수 임계치 직전 초과(-1.000001s slow): FAIL
write_tracking "1.000001000 seconds slow of NTP time" "Normal"; write_sources "34"
run_script env
expect "just-over-slow offset" "$(jget offset detail)" "-1.000001"
expect "just-over-slow offset_budget" "$(jget offset_budget status)" FAIL
expect "just-over-slow offset_budget detail" "$(jget offset_budget detail)" "offset=-1.000001;budget=1.0"
expect "just-over-slow overall" "$(jget - status)" FAIL
expect "just-over-slow rc" "$RC" 1

# - 음수 예산 이내(-0.5s slow): 문자열 비교가 아닌 수치 비교 검증
write_tracking "0.500000000 seconds slow of NTP time" "Normal"; write_sources "34"
run_script env
expect "within-budget-slow offset" "$(jget offset detail)" "-0.5"
expect "within-budget-slow offset_budget" "$(jget offset_budget status)" PASS
expect "within-budget-slow offset_budget detail" "$(jget offset_budget detail)" "offset=-0.5;budget=1.0"

# 10.2. source_freshness 수치 임계치 경계(기본 한도 3600s: 3600s/60m/1h PASS, 3601s/61m FAIL)
# - 정확히 한도(3600s, 60m, 1h): 모두 age=3600으로 PASS
write_tracking "0.000100000 seconds fast of NTP time" "Normal"
write_sources "3600s"
run_script env
expect "exact-age-sec freshness" "$(jget source_freshness status)" PASS
expect "exact-age-sec detail" "$(jget source_freshness detail)" "age=3600;max=3600"

write_sources "60m"
run_script env
expect "exact-age-min freshness" "$(jget source_freshness status)" PASS
expect "exact-age-min detail" "$(jget source_freshness detail)" "age=3600;max=3600"

write_sources "1h"
run_script env
expect "exact-age-hr freshness" "$(jget source_freshness status)" PASS
expect "exact-age-hr detail" "$(jget source_freshness detail)" "age=3600;max=3600"

# - 한도 직전 초과(3601s, 61m): FAIL
write_sources "3601s"
run_script env
expect "just-over-age-sec freshness" "$(jget source_freshness status)" FAIL
expect "just-over-age-sec detail" "$(jget source_freshness detail)" "age=3601;max=3600"
expect "just-over-age-sec overall" "$(jget - status)" FAIL
expect "just-over-age-sec rc" "$RC" 1

write_sources "61m"
run_script env
expect "just-over-age-min freshness" "$(jget source_freshness status)" FAIL
expect "just-over-age-min detail" "$(jget source_freshness detail)" "age=3660;max=3600"
expect "just-over-age-min overall" "$(jget - status)" FAIL
expect "just-over-age-min rc" "$RC" 1

# 10.3. Leap status 변형 (Insert second, Delete second 등 비정상 leap status -> FAIL)
write_tracking "0.000100000 seconds fast of NTP time" "Insert second"; write_sources "34"
run_script env
expect "leap-insert synchronized" "$(jget synchronized status)" FAIL
expect "leap-insert synchronized detail" "$(jget synchronized detail)" unsynchronized
expect "leap-insert overall" "$(jget - status)" FAIL
expect "leap-insert rc" "$RC" 1

write_tracking "0.000100000 seconds fast of NTP time" "Delete second"; write_sources "34"
run_script env
expect "leap-delete synchronized" "$(jget synchronized status)" FAIL
expect "leap-delete synchronized detail" "$(jget synchronized detail)" unsynchronized

# 10.4. 지수 표기법(scientific notation) 및 비정상/파싱 불가 chronyc 출력
# - System time에 지수 표기(1.0e-04): chronyc 표준은 고정소수점이므로 정규식 불일치 -> UNKNOWN
write_tracking "1.000000000e-04 seconds fast of NTP time" "Normal"; write_sources "34"
run_script env
expect "sci-notation offset" "$(jget offset status)" UNKNOWN
expect "sci-notation offset detail" "$(jget offset detail)" not-reported
expect "sci-notation offset_budget" "$(jget offset_budget status)" UNKNOWN
expect "sci-notation offset_budget detail" "$(jget offset_budget detail)" offset-unknown

# - System time 파싱 불가 문자열 -> UNKNOWN
write_tracking "unexpected non-numeric output" "Normal"; write_sources "34"
run_script env
expect "unparseable-tracking offset" "$(jget offset status)" UNKNOWN
expect "unparseable-tracking offset detail" "$(jget offset detail)" not-reported
expect "unparseable-tracking offset_budget" "$(jget offset_budget status)" UNKNOWN
expect "unparseable-tracking offset_budget detail" "$(jget offset_budget detail)" offset-unknown

# - sources LastRx 파싱 불가('-' 미응답 또는 알 수 없는 접미사 '10x') -> source_freshness UNKNOWN
write_tracking "0.000100000 seconds fast of NTP time" "Normal"; write_sources "-"
run_script env
expect "dash-lastrx freshness" "$(jget source_freshness status)" UNKNOWN
expect "dash-lastrx freshness detail" "$(jget source_freshness detail)" unavailable

write_sources "10x"
run_script env
expect "invalid-suffix-lastrx freshness" "$(jget source_freshness status)" UNKNOWN
expect "invalid-suffix-lastrx freshness detail" "$(jget source_freshness detail)" unavailable

# 10.5. chronyc 실행 실패(출력 없이 비정상 종료 STUB_RC=1) -> FAIL 또는 UNKNOWN, 절대 PASS 아님
: >"$WORKDIR/tracking"; : >"$WORKDIR/sources"
run_script env STUB_RC=1
expect "nonzero-rc synchronized" "$(jget synchronized status)" FAIL
expect "nonzero-rc offset" "$(jget offset status)" UNKNOWN
expect "nonzero-rc offset_budget" "$(jget offset_budget status)" UNKNOWN
expect "nonzero-rc sources" "$(jget sources status)" FAIL
expect "nonzero-rc freshness" "$(jget source_freshness status)" UNKNOWN
expect "nonzero-rc overall" "$(jget - status)" FAIL
expect "nonzero-rc rc" "$RC" 1

# 10.6. chronyc 부재: PATH에 chronyc가 없으면 FAIL missing 및 관련 체크 UNKNOWN, 전체 FAIL
NOCHRONY="$WORKDIR/nochrony"; mkdir -p "$NOCHRONY"
for t in bash env python3 date awk grep tr cat wc sed dirname head ls pgrep timedatectl openssl; do
  p=$(command -v "$t" 2>/dev/null || true); [ -n "$p" ] && ln -sf "$p" "$NOCHRONY/$t"
done
set +e
PATH="$NOCHRONY" STUB_TRACKING="$WORKDIR/tracking" STUB_SOURCES="$WORKDIR/sources" \
  "$NOCHRONY/bash" "$SCRIPT" >"$OUT" 2>"$WORKDIR/err.log"
RC=$?
set -e
expect "absent chrony_installed" "$(jget chrony_installed status)" FAIL
expect "absent chrony_installed detail" "$(jget chrony_installed detail)" missing
expect "absent offset" "$(jget offset status)" UNKNOWN
expect "absent offset detail" "$(jget offset detail)" unavailable
expect "absent sources" "$(jget sources status)" UNKNOWN
expect "absent sources detail" "$(jget sources detail)" unavailable
expect "absent freshness" "$(jget source_freshness status)" UNKNOWN
expect "absent freshness detail" "$(jget source_freshness detail)" unavailable
expect "absent offset_budget" "$(jget offset_budget status)" UNKNOWN
expect "absent offset_budget detail" "$(jget offset_budget detail)" offset-unknown
expect "absent overall" "$(jget - status)" FAIL
expect "absent rc" "$RC" 1

# 11. 인증서 clock sanity (#19): openssl로 테스트 시점에 fixture 인증서를 만든다.
#     chronyc stub은 정상 동기화 상태로 두어 cert_clock_sanity만 바뀌게 한다.
if command -v openssl >/dev/null 2>&1; then
  CERTS="$WORKDIR/certs"; mkdir -p "$CERTS/valid" "$CERTS/mixed" "$CERTS/bad" "$CERTS/none"
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$CERTS/k.pem" -subj /CN=t \
    -days 365 -out "$CERTS/valid/a.crt" 2>/dev/null
  NOW=$(date -u +%s)
  write_tracking "0.000100000 seconds fast of NTP time" "Normal"; write_sources "34"
  # valid: 지금 기준 유효
  run_script env TIME_READINESS_CERT_PATHS="$CERTS/valid/*.crt"
  expect "cert valid" "$(jget cert_clock_sanity status)" PASS
  expect "cert valid overall" "$(jget - status)" PASS
  # not-yet-valid: 같은 인증서, 기준 시각을 NotBefore 이전(1년 전)으로
  run_script env TIME_READINESS_CERT_PATHS="$CERTS/valid/*.crt" TIME_READINESS_NOW=$((NOW - 31536000))
  expect "cert future status" "$(jget cert_clock_sanity status)" FAIL
  expect "cert future detail" "$(jget cert_clock_sanity detail)" "$CERTS/valid/a.crt:not-yet-valid"
  expect "cert future overall" "$(jget - status)" FAIL
  # expired: 기준 시각을 NotAfter 이후(2년 뒤)로
  run_script env TIME_READINESS_CERT_PATHS="$CERTS/valid/*.crt" TIME_READINESS_NOW=$((NOW + 63072000))
  expect "cert expired status" "$(jget cert_clock_sanity status)" FAIL
  expect "cert expired detail" "$(jget cert_clock_sanity detail)" "$CERTS/valid/a.crt:expired"
  expect "cert expired overall" "$(jget - status)" FAIL
  expect "cert expired rc" "$RC" 1
  # none: 일치하는 인증서 없음 -> UNKNOWN (PASS 아님), 전체 status는 FAIL 아님
  run_script env TIME_READINESS_CERT_PATHS="$CERTS/none/*.crt"
  expect "cert none status" "$(jget cert_clock_sanity status)" UNKNOWN
  expect "cert none detail" "$(jget cert_clock_sanity detail)" no-certificates
  expect "cert none overall" "$(jget - status)" PASS
  # 파싱 불가 파일만 있으면 UNKNOWN (전체 status는 FAIL이 아니므로 PASS, rc 0)
  echo garbage >"$CERTS/bad/bad.crt"
  run_script env TIME_READINESS_CERT_PATHS="$CERTS/bad/*.crt"
  expect "cert unparseable status" "$(jget cert_clock_sanity status)" UNKNOWN
  expect "cert unparseable detail" "$(jget cert_clock_sanity detail)" "unparseable=1;valid=0"
  expect "cert unparseable overall" "$(jget - status)" PASS
  expect "cert unparseable rc" "$RC" 0
  # valid + 파싱 불가 혼합 -> UNKNOWN (PASS로 승격 금지)
  cp "$CERTS/valid/a.crt" "$CERTS/mixed/a.crt"; echo garbage >"$CERTS/mixed/z.crt"
  run_script env TIME_READINESS_CERT_PATHS="$CERTS/mixed/*.crt"
  expect "cert mixed-unparseable status" "$(jget cert_clock_sanity status)" UNKNOWN
  expect "cert mixed-unparseable detail" "$(jget cert_clock_sanity detail)" "unparseable=1;valid=1"
  # valid(a) + expired(b, 기준 시각 +2일) + 파싱 불가(z) 혼합 -> FAIL이 UNKNOWN/PASS보다 우선 (파싱 불가 파일이 섞여도)
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$CERTS/k2.pem" -subj /CN=short \
    -days 1 -out "$CERTS/mixed/b.crt" 2>/dev/null
  run_script env TIME_READINESS_CERT_PATHS="$CERTS/mixed/*.crt" TIME_READINESS_NOW=$((NOW + 172800))
  expect "cert mixed-expired status" "$(jget cert_clock_sanity status)" FAIL
  expect "cert mixed-expired detail" "$(jget cert_clock_sanity detail)" "$CERTS/mixed/b.crt:expired"
  # openssl 없음: openssl을 뺀 PATH 심 -> UNKNOWN openssl-missing
  NOSSL="$WORKDIR/nossl"; mkdir -p "$NOSSL"
  for t in bash env python3 date awk grep tr cat wc sed dirname head ls pgrep timedatectl; do
    p=$(command -v "$t" 2>/dev/null || true); [ -n "$p" ] && ln -sf "$p" "$NOSSL/$t"
  done
  ln -sf "$STUBBIN/chronyc" "$NOSSL/chronyc"
  set +e
  PATH="$NOSSL" STUB_TRACKING="$WORKDIR/tracking" STUB_SOURCES="$WORKDIR/sources" \
    TIME_READINESS_CERT_PATHS="$CERTS/valid/*.crt" "$NOSSL/bash" "$SCRIPT" >"$OUT" 2>"$WORKDIR/err.log"
  RC=$?
  set -e
  expect "cert no-openssl status" "$(jget cert_clock_sanity status)" UNKNOWN
  expect "cert no-openssl detail" "$(jget cert_clock_sanity detail)" openssl-missing
else
  echo "SKIP: openssl not found, cert_clock_sanity scenarios not run" >&2
fi

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
echo "node-time-readiness-test: all scenarios passed"
