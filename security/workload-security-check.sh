#!/usr/bin/env bash
set -euo pipefail
checks=(); failures=0; unknowns=0
add(){ local id=$1 st=$2 d=$3; checks+=("{\"id\":\"$id\",\"status\":\"$st\",\"detail\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$d")}"); [ "$st" = FAIL ] && failures=$((failures+1)); [ "$st" = UNKNOWN ] && unknowns=$((unknowns+1)); }

. /etc/os-release
if [ "$ID" = ubuntu ]; then
  command -v aa-status >/dev/null 2>&1 && aa-status --enabled >/dev/null 2>&1 && add apparmor PASS enabled || add apparmor UNKNOWN unavailable
  add mac_backend PASS AppArmor
elif [ "$ID" = rocky ] || [ "$ID" = rhel ]; then
  state=$(getenforce 2>/dev/null || echo unavailable)
  case "$state" in Enforcing) add selinux PASS Enforcing;; Permissive|Disabled) add selinux FAIL "$state";; *) add selinux UNKNOWN "$state";; esac
  add mac_backend PASS SELinux
else add mac_backend UNKNOWN "$ID"; fi

[ -r /proc/self/status ] && grep -q '^Seccomp:' /proc/self/status && add seccomp PASS kernel-interface || add seccomp UNKNOWN unavailable

if command -v crictl >/dev/null 2>&1; then
  add runtime_probe PASS crictl-present
elif command -v ctr >/dev/null 2>&1; then
  add runtime_probe PASS ctr-present
else add runtime_probe UNKNOWN no-CRI-tool; fi

# Privileged/host namespace settings are workload-level risks and cannot be
# inferred safely from a node-only image. Require an explicit workload report.
if [ "${WORKLOAD_PRIVILEGED:-0}" = 1 ]; then add privileged_workload FAIL "privileged workload weakens MAC/seccomp guarantees"; else add privileged_workload PASS "not declared privileged"; fi

status=PASS; [ "$failures" -gt 0 ] && status=FAIL
printf '{"schema":"kube-ready-security/v1","kind":"workload-security","status":"%s","os":"%s","checks":[%s],"failures":%d,"unknowns":%d}\n' "$status" "$ID" "$(IFS=,; echo "${checks[*]}")" "$failures" "$unknowns"
[ "$status" = PASS ]
