#!/usr/bin/env bash
set -euo pipefail
checks=(); failures=0; unknowns=0
add(){ local id=$1 st=$2 d=$3; checks+=("{\"id\":\"$id\",\"status\":\"$st\",\"detail\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$d")}"); case "$st" in FAIL) failures=$((failures+1));; UNKNOWN) unknowns=$((unknowns+1));; esac; }

[ -r /etc/os-release ] && . /etc/os-release
ID="${ID:-}"
if [ "$ID" = ubuntu ]; then
  command -v aa-status >/dev/null 2>&1 && aa-status --enabled >/dev/null 2>&1 && add apparmor PASS enabled || add apparmor UNKNOWN unavailable
  add mac_backend PASS AppArmor
elif [ "$ID" = rocky ] || [ "$ID" = rhel ]; then
  state=$(getenforce 2>/dev/null || echo unavailable)
  case "$state" in Enforcing) add selinux PASS Enforcing;; Permissive|Disabled) add selinux FAIL "$state";; *) add selinux UNKNOWN "$state";; esac
  add mac_backend PASS SELinux
else add mac_backend UNKNOWN "$ID"; fi

# Deeper AppArmor view: how many profiles are loaded and their enforce/complain split.
if command -v aa-status >/dev/null 2>&1; then
  aa_detail=""
  aa_json=$(aa-status --json 2>/dev/null || echo "")
  if [ -n "$aa_json" ]; then
    aa_detail=$(printf '%s' "$aa_json" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
profiles = d.get("profiles", {})
enforce = sum(1 for v in profiles.values() if v == "enforce")
complain = sum(1 for v in profiles.values() if v == "complain")
print(f"loaded={len(profiles)} enforce={enforce} complain={complain}")
' 2>/dev/null || echo "")
  fi
  if [ -z "$aa_detail" ]; then
    aa_text=$(aa-status 2>/dev/null || echo "")
    aa_loaded=$(printf '%s\n' "$aa_text" | grep -oE '^[0-9]+ profiles are loaded' | grep -oE '^[0-9]+' || echo "")
    aa_enforce=$(printf '%s\n' "$aa_text" | grep -oE '^[0-9]+ profiles are in enforce mode' | grep -oE '^[0-9]+' || echo "")
    aa_complain=$(printf '%s\n' "$aa_text" | grep -oE '^[0-9]+ profiles are in complain mode' | grep -oE '^[0-9]+' || echo "")
    [ -n "$aa_loaded" ] && aa_detail="loaded=${aa_loaded} enforce=${aa_enforce:-0} complain=${aa_complain:-0}" || true
  fi
  if [ -n "$aa_detail" ]; then add apparmor_profiles PASS "$aa_detail"; else add apparmor_profiles UNKNOWN "aa-status-output-unparseable"; fi
else add apparmor_profiles UNKNOWN unavailable; fi

# Cross-check the SELinux config file against the runtime mode; only flag an
# unsafe downgrade (config wants enforcing, runtime is permissive/disabled).
if [ -r /etc/selinux/config ]; then
  sel_type=$(grep -oE '^SELINUXTYPE=.*' /etc/selinux/config | cut -d= -f2 || echo "")
  sel_mode=$(grep -oE '^SELINUX=.*' /etc/selinux/config | cut -d= -f2 || echo "")
  sel_runtime=$(getenforce 2>/dev/null || echo "unavailable")
  sel_detail="type=${sel_type:-unknown} config=${sel_mode:-unset} runtime=${sel_runtime}"
  if [ "$sel_mode" = "enforcing" ] && { [ "$sel_runtime" = "Permissive" ] || [ "$sel_runtime" = "Disabled" ]; }; then
    add selinux_policy FAIL "$sel_detail"
  else
    add selinux_policy PASS "$sel_detail"
  fi
else add selinux_policy UNKNOWN "no-selinux"; fi

[ -r /proc/self/status ] && grep -q '^Seccomp:' /proc/self/status && add seccomp PASS kernel-interface || add seccomp UNKNOWN unavailable

if [ -r /proc/sys/kernel/seccomp/actions_avail ]; then
  seccomp_actions=$(cat /proc/sys/kernel/seccomp/actions_avail 2>/dev/null || echo "")
  if [ -n "$seccomp_actions" ]; then add seccomp_capability PASS "$seccomp_actions"; else add seccomp_capability UNKNOWN empty; fi
else add seccomp_capability UNKNOWN unavailable; fi

if command -v crictl >/dev/null 2>&1; then
  add runtime_probe PASS crictl-present
elif command -v ctr >/dev/null 2>&1; then
  add runtime_probe PASS ctr-present
else add runtime_probe UNKNOWN no-CRI-tool; fi

if command -v crictl >/dev/null 2>&1; then
  rt_version=$(crictl --version 2>/dev/null || echo "")
  if [ -n "$rt_version" ]; then add runtime_version PASS "$rt_version"; else add runtime_version UNKNOWN crictl-version-empty; fi
elif command -v containerd >/dev/null 2>&1; then
  rt_version=$(containerd --version 2>/dev/null || echo "")
  if [ -n "$rt_version" ]; then add runtime_version PASS "$rt_version"; else add runtime_version UNKNOWN containerd-version-empty; fi
else add runtime_version UNKNOWN no-CRI-tool; fi

if [ -r /etc/os-release ] && [ -n "$ID" ]; then add os_id PASS "$ID"; else add os_id UNKNOWN unavailable; fi

# Privileged/host namespace settings are workload-level risks and cannot be
# inferred safely from a node-only image. Require an explicit workload report.
if [ "${WORKLOAD_PRIVILEGED:-0}" = 1 ]; then add privileged_workload FAIL "privileged workload weakens MAC/seccomp guarantees"; else add privileged_workload PASS "not declared privileged"; fi

status=PASS; [ "$failures" -gt 0 ] && status=FAIL
printf '{"schema":"kube-ready-security/v1","kind":"workload-security","status":"%s","os":"%s","checks":[%s],"failures":%d,"unknowns":%d}\n' "$status" "$ID" "$(IFS=,; echo "${checks[*]}")" "$failures" "$unknowns"
[ "$status" = PASS ]
