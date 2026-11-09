#!/usr/bin/env bash
set -euo pipefail
checks=(); failures=0; unknowns=0
add(){ local id=$1 st=$2 d=$3; checks+=("{\"id\":\"$id\",\"status\":\"$st\",\"detail\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$d")}"); case "$st" in FAIL) failures=$((failures+1));; UNKNOWN) unknowns=$((unknowns+1));; esac; }

offset=""

if command -v chronyc >/dev/null 2>&1; then
  add chrony_installed PASS present
  tracking=$(chronyc tracking 2>/dev/null || true)
  if echo "$tracking" | grep -q 'Leap status.*Normal'; then add synchronized PASS normal; else add synchronized FAIL unsynchronized; fi

  offset=$(printf '%s\n' "$tracking" | python3 -c '
import sys, re
line = ""
for l in sys.stdin:
    if "System time" in l:
        line = l
        break
m = re.search(r":\s*([-+]?[0-9.]+)\s*seconds\s*(slow|fast)\s*of\s*NTP\s*time", line)
if m:
    val = float(m.group(1))
    if m.group(2) == "slow":
        val = -val
    print(val)
' 2>/dev/null || true)
  if [ -n "$offset" ]; then add offset PASS "$offset"; else add offset UNKNOWN not-reported; fi

  # pipefail 아래서 chronyc가 데몬에 연결 못 하면(FAIL만이 아니라) 이 파이프
  # 자체가 죽어 스크립트가 JSON을 아예 출력하지 못한다(#13 negative test로
  # 실제 발견됨 - chronyd를 실제로 멈추기 전엔 드러나지 않았던 결함). wc -l은
  # chronyc가 아무것도 못 내놔도 정상적으로 0을 세므로, 파이프 실패만 흡수하면
  # sources 값 자체는 이미 올바르게 "0"이 된다.
  sources=$(chronyc sources -n 2>/dev/null | awk 'NR>2 && $1 ~ /^[\^=#]/ {print}' | wc -l) || true
  if [ "$sources" -gt 0 ]; then add sources PASS "$sources"; else add sources FAIL zero-configured-sources; fi

  best_line=$(chronyc sources -v 2>/dev/null | awk '/^\^\*/{print; exit}' || true)
  source_age=""
  if [ -n "$best_line" ]; then
    lastrx=$(echo "$best_line" | awk '{print $6}') || true
    source_age=$(python3 -c '
import re, sys
s = sys.argv[1]
m = re.match(r"^([0-9]+)([smhd]?)$", s)
if not m:
    sys.exit(1)
val = int(m.group(1))
mult = {"": 1, "s": 1, "m": 60, "h": 3600, "d": 86400}[m.group(2)]
print(val * mult)
' "$lastrx" 2>/dev/null || true)
  fi
  max_age="${TIME_READINESS_MAX_SOURCE_AGE_SECONDS:-3600}"
  if [ -z "$source_age" ]; then
    add source_freshness UNKNOWN unavailable
  elif [ "$source_age" -le "$max_age" ]; then
    add source_freshness PASS "age=${source_age};max=${max_age}"
  else
    add source_freshness FAIL "age=${source_age};max=${max_age}"
  fi
else
  add chrony_installed FAIL missing
  add offset UNKNOWN unavailable
  add sources UNKNOWN unavailable
  add source_freshness UNKNOWN unavailable
fi

if [ -r /sys/devices/system/clocksource/clocksource0/current_clocksource ]; then add clocksource PASS "$(cat /sys/devices/system/clocksource/clocksource0/current_clocksource)"; else add clocksource UNKNOWN unavailable; fi

if command -v timedatectl >/dev/null 2>&1; then timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -qi yes && add timedatectl_sync PASS yes || add timedatectl_sync UNKNOWN no; else add timedatectl_sync UNKNOWN unavailable; fi

max_offset="${TIME_READINESS_MAX_OFFSET_SECONDS:-1.0}"
if [ -z "$offset" ]; then
  add offset_budget UNKNOWN offset-unknown
else
  within=$(python3 -c '
import sys
offset = float(sys.argv[1])
budget = float(sys.argv[2])
print(1 if abs(offset) <= budget else 0)
' "$offset" "$max_offset" 2>/dev/null || true)
  if [ "$within" = "1" ]; then
    add offset_budget PASS "offset=${offset};budget=${max_offset}"
  elif [ "$within" = "0" ]; then
    add offset_budget FAIL "offset=${offset};budget=${max_offset}"
  else
    add offset_budget UNKNOWN compare-failed
  fi
fi

if [ -e /dev/ptp0 ] || ls /dev/ptp* >/dev/null 2>&1; then
  if command -v pgrep >/dev/null 2>&1 && pgrep -x ptp4l >/dev/null 2>&1; then
    add ptp PASS active
  else
    add ptp PASS capability-only
  fi
else
  add ptp UNKNOWN unavailable
fi

# 인증서 clock sanity: 노드 시계가 인증서 유효기간(NotBefore~NotAfter) 밖이면 TLS가
# 깨진다. 경로는 TIME_READINESS_CERT_PATHS(공백 구분 glob)로 덮어쓰고 기준 시각은
# TIME_READINESS_NOW(epoch)로 고정할 수 있다(fixture용). 검사할 인증서가 없거나
# openssl이 없으면 "아무것도 검사하지 않음"이므로 PASS가 아니라 UNKNOWN이다.
cert_now="${TIME_READINESS_NOW:-$(date -u +%s)}"
cert_files=()
# shellcheck disable=SC2086
for f in ${TIME_READINESS_CERT_PATHS:-/etc/kubernetes/pki/*.crt /var/lib/kubelet/pki/*.crt}; do
  [ -f "$f" ] && cert_files+=("$f")
done
if ! command -v openssl >/dev/null 2>&1; then
  add cert_clock_sanity UNKNOWN openssl-missing
elif [ "${#cert_files[@]}" -eq 0 ]; then
  add cert_clock_sanity UNKNOWN no-certificates
else
  cert_dates=""
  for f in "${cert_files[@]}"; do
    d=$(openssl x509 -in "$f" -noout -startdate -enddate 2>/dev/null | tr '\n' ' ') || d=""
    cert_dates+="$f|$d"$'\n'
  done
  cert_result=$(printf '%s' "$cert_dates" | python3 -c '
import sys, re, calendar, time
now = int(sys.argv[1])
bad, unread, ok = [], 0, 0
for line in sys.stdin:
    path, _, d = line.rstrip("\n").partition("|")
    m = re.search(r"notBefore=(.+?GMT)\s+notAfter=(.+?GMT)", d)
    try:
        nb = calendar.timegm(time.strptime(" ".join(m.group(1).split()), "%b %d %H:%M:%S %Y GMT"))
        na = calendar.timegm(time.strptime(" ".join(m.group(2).split()), "%b %d %H:%M:%S %Y GMT"))
    except Exception:
        unread += 1
        continue
    if now < nb:
        bad.append(path + ":not-yet-valid")
    elif now > na:
        bad.append(path + ":expired")
    else:
        ok += 1
print("FAIL " + ",".join(bad) if bad else ("UNKNOWN unparseable=%d;valid=%d" % (unread, ok) if unread or not ok else "PASS valid=%d" % ok))
' "$cert_now" 2>/dev/null || true)
  case "$cert_result" in
    FAIL\ *|PASS\ *|UNKNOWN\ *) add cert_clock_sanity "${cert_result%% *}" "${cert_result#* }" ;;
    *) add cert_clock_sanity UNKNOWN check-failed ;;
  esac
fi

if [ -r /etc/os-release ]; then
  os_id=$(awk -F= '/^ID=/{gsub(/"/,"",$2); print $2; exit}' /etc/os-release) || true
  if [ -n "$os_id" ]; then add os_id PASS "$os_id"; else add os_id UNKNOWN unavailable; fi
else
  add os_id UNKNOWN unavailable
fi

now=$(date -u +%s); add clock_epoch PASS "$now"
status=PASS; [ "$failures" -gt 0 ] && status=FAIL
printf '{"schema":"kube-ready-time/v1","kind":"node-time-readiness","status":"%s","checks":[%s],"failures":%d,"unknowns":%d}\n' "$status" "$(IFS=,; echo "${checks[*]}")" "$failures" "$unknowns"
[ "$status" = PASS ]
