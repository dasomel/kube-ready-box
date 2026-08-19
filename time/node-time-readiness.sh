#!/usr/bin/env bash
set -euo pipefail
checks=(); failures=0; unknowns=0
add(){ local id=$1 st=$2 d=$3; checks+=("{\"id\":\"$id\",\"status\":\"$st\",\"detail\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$d")}"); [ "$st" = FAIL ] && failures=$((failures+1)); [ "$st" = UNKNOWN ] && unknowns=$((unknowns+1)); }

if command -v chronyc >/dev/null 2>&1; then
  add chrony_installed PASS present
  tracking=$(chronyc tracking 2>/dev/null || true)
  if echo "$tracking" | grep -q 'Leap status.*Normal'; then add synchronized PASS normal; else add synchronized FAIL unsynchronized; fi
  offset=$(echo "$tracking" | awk -F: '/Last offset/{gsub(/ /,"",$2);print $2;exit}')
  add offset UNKNOWN "${offset:-not-reported}"
  sources=$(chronyc sources -n 2>/dev/null | awk 'NR>2 && $1 ~ /^[\^=#]/ {print}' | wc -l)
  [ "$sources" -gt 0 ] && add sources PASS "$sources" || add sources UNKNOWN none
else add chrony_installed FAIL missing; fi

if [ -r /sys/devices/system/clocksource/clocksource0/current_clocksource ]; then add clocksource PASS "$(cat /sys/devices/system/clocksource/clocksource0/current_clocksource)"; else add clocksource UNKNOWN unavailable; fi

if command -v timedatectl >/dev/null 2>&1; then timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -qi yes && add timedatectl_sync PASS yes || add timedatectl_sync UNKNOWN no; else add timedatectl_sync UNKNOWN unavailable; fi

if [ -n "${TIME_READINESS_MAX_OFFSET:-}" ]; then add offset_budget UNKNOWN "configured=${TIME_READINESS_MAX_OFFSET}; numeric normalization is backend-specific"; else add offset_budget UNKNOWN not-configured; fi

if [ -e /dev/ptp0 ] || ls /dev/ptp* >/dev/null 2>&1; then add ptp PASS device-present; else add ptp UNKNOWN unavailable; fi

now=$(date -u +%s); add clock_epoch PASS "$now"
status=PASS; [ "$failures" -gt 0 ] && status=FAIL
printf '{"schema":"kube-ready-time/v1","kind":"node-time-readiness","status":"%s","checks":[%s],"failures":%d,"unknowns":%d}\n' "$status" "$(IFS=,; echo "${checks[*]}")" "$failures" "$unknowns"
[ "$status" = PASS ]
