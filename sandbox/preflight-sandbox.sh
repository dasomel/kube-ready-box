#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

PROFILE="${SANDBOX_PROFILE:-standard}"
REPORT="${SANDBOX_REPORT:-/tmp/kube-ready-box-sandbox.json}"
failures=0
unknowns=0

check(){
  local id="$1" status="$2" detail="$3"
  printf '%s\t%s\t%s\n' "$id" "$status" "$detail"
  [ "$status" = FAIL ] && failures=$((failures+1))
  [ "$status" = UNKNOWN ] && unknowns=$((unknowns+1))
}

if command -v runsc >/dev/null 2>&1; then
  runsc_version="$(runsc --version 2>&1 | head -n1)"
  check runsc PASS "$runsc_version"
else
  runsc_version=""
  if [ "$PROFILE" = standard ]; then check runsc UNKNOWN not-installed; else check runsc FAIL not-installed; fi
fi

if systemctl cat containerd >/dev/null 2>&1; then
  if grep -Eq 'runtimes\.runsc|io\.containerd\.runsc\.v1' /etc/containerd/config.toml 2>/dev/null; then
    check containerd_runsc_handler PASS configured
  elif [ "$PROFILE" = standard ]; then
    check containerd_runsc_handler UNKNOWN not-configured
  else
    check containerd_runsc_handler FAIL not-configured
  fi
else
  check containerd_runsc_handler UNKNOWN containerd-not-installed
fi

if [ -r /proc/sys/kernel/unprivileged_userns_clone ]; then
  check user_namespace PASS "$(cat /proc/sys/kernel/unprivileged_userns_clone)"
else
  check user_namespace UNKNOWN sysctl-not-present
fi

if [ -r /proc/sys/kernel/pid_max ]; then check pid_limit PASS "$(cat /proc/sys/kernel/pid_max)"; else check pid_limit UNKNOWN unavailable; fi

for module in overlay br_netfilter; do
  if lsmod 2>/dev/null | awk '{print $1}' | grep -qx "$module"; then check "module_$module" PASS loaded; else check "module_$module" UNKNOWN not-loaded; fi
done

status=PASS
[ "$failures" -gt 0 ] && status=FAIL
cat > "$REPORT" <<EOF
{
  "schema_version": 1,
  "profile": "$PROFILE",
  "status": "$status",
  "failures": $failures,
  "unknowns": $unknowns,
  "runsc_version": "$runsc_version"
}
EOF
cat "$REPORT"
[ "$status" = PASS ]
