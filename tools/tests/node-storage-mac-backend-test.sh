#!/usr/bin/env bash
# Deterministic fixture coverage for #44 T-021 (REQ-003, AC-003, AC-004,
# D4): storage/node-storage-readiness.sh's `mac_backend` check must not PASS
# for a disabled AppArmor or a permissive/disabled SELinux (the false-green
# fixed here: "PASS apparmor:disabled" and "PASS selinux:Permissive").
#
# PATH is an isolated symlink farm of only the real utilities the script
# unconditionally needs (python3 for every add() call, plus grep/cut/tr/df/
# awk for the checks ahead of mac_backend), so no real getenforce/aa-status
# on the test host can leak into a scenario -- each scenario controls
# getenforce/aa-status/the AppArmor sysfs parameter explicitly. This is the
# same isolation technique as tools/tests/network-firewall-detection-test.sh;
# the AppArmor sysfs read itself is shimmed the way
# tools/tests/workload-lsm-stack-test.sh shims `cat` (D7: no production
# env-var bypass for the /sys path). Must pass on both macOS and Linux.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/storage/node-storage-readiness.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

essentials_dir="$WORKDIR/essentials"
mkdir -p "$essentials_dir"
for tool in bash python3 grep cut tr df awk printf tail head; do
  real=$(command -v "$tool" 2>/dev/null || true)
  [ -n "$real" ] && ln -sf "$real" "$essentials_dir/$tool"
done

# write_scenario_bin <bindir> [selinux_state] [apparmor_mode] [apparmor_value] [aa_status_mode]
# selinux_state: unset (no getenforce shim, i.e. selinux absent) or a getenforce
# stdout value (Enforcing/Permissive/Disabled/<anything else>).
# apparmor_mode: absent (cat errors: No such file or directory) or present
# (cat prints apparmor_value).
# aa_status_mode: absent (no aa-status shim) or enabled/disabled (aa-status
# --enabled exit 0/1) -- only reachable when selinux is absent and the
# AppArmor sysfs parameter is itself absent.
write_scenario_bin() {
  local bindir=$1 selinux_state=${2:-} apparmor_mode=${3:-absent} apparmor_value=${4:-} aa_status_mode=${5:-absent}
  mkdir -p "$bindir"
  for f in "$essentials_dir"/*; do ln -sf "$f" "$bindir/$(basename "$f")"; done

  if [ -n "$selinux_state" ]; then
    cat > "$bindir/getenforce" <<SHIM
#!/usr/bin/env bash
printf '%s\n' "$selinux_state"
SHIM
    chmod +x "$bindir/getenforce"
  fi

  local real_cat
  real_cat=$(command -v cat)
  cat > "$bindir/cat" <<SHIM
#!/usr/bin/env bash
set -euo pipefail
if [ "\$#" -eq 1 ] && [ "\$1" = "/sys/module/apparmor/parameters/enabled" ]; then
  case "$apparmor_mode" in
    present)
      printf '%s\n' "$apparmor_value"
      exit 0
      ;;
    absent)
      echo "cat: /sys/module/apparmor/parameters/enabled: No such file or directory" >&2
      exit 1
      ;;
  esac
fi
exec "$real_cat" "\$@"
SHIM
  chmod +x "$bindir/cat"

  if [ "$aa_status_mode" != "absent" ]; then
    cat > "$bindir/aa-status" <<SHIM
#!/usr/bin/env bash
[ "\$1" = "--enabled" ] || exit 1
[ "$aa_status_mode" = "enabled" ]
SHIM
    chmod +x "$bindir/aa-status"
  fi
}

assert_check() {
  local out=$1 id=$2 status=$3 detail=$4
  python3 - "$out" "$id" "$status" "$detail" <<'PY'
import json, sys
path, check_id, expected_status, expected_detail = sys.argv[1:]
checks = json.load(open(path, encoding="utf-8")).get("checks", [])
matches = [c for c in checks if c.get("id") == check_id]
if len(matches) != 1:
    print(f"::error::{path}: expected exactly one check id={check_id!r}, found {len(matches)}")
    raise SystemExit(1)
actual_status, actual_detail = matches[0].get("status"), matches[0].get("detail")
if actual_status != expected_status or actual_detail != expected_detail:
    print(f"::error::{path}: {check_id!r} expected {expected_status}/{expected_detail!r}, "
          f"got {actual_status}/{actual_detail!r}")
    raise SystemExit(1)
PY
}

run_case() {
  local name=$1; shift
  local bindir="$WORKDIR/bin-$name"
  write_scenario_bin "$bindir" "$@"
  local out="$WORKDIR/$name.json"
  set +e
  PATH="$bindir" bash "$SCRIPT" >"$out" 2>"$WORKDIR/$name.stderr"
  set -e
  python3 -m json.tool "$out" >/dev/null || {
    echo "::error::$name did not produce parseable JSON" >&2
    cat "$WORKDIR/$name.stderr" >&2
    exit 1
  }
  echo "$out"
}

# --- SELinux: Enforcing -> PASS ---
out=$(run_case selinux-enforcing Enforcing)
assert_check "$out" mac_backend PASS "selinux:Enforcing"

# --- SELinux: Permissive -> FAIL, not PASS (the false-green this fixes) ---
out=$(run_case selinux-permissive Permissive)
assert_check "$out" mac_backend FAIL "selinux:Permissive"

# --- SELinux: Disabled -> FAIL ---
out=$(run_case selinux-disabled Disabled)
assert_check "$out" mac_backend FAIL "selinux:Disabled"

# --- SELinux: unexpected getenforce output -> UNKNOWN, never PASS/FAIL ---
out=$(run_case selinux-unexpected garbled)
assert_check "$out" mac_backend UNKNOWN "selinux:garbled"

# --- AppArmor: enabled (Y) -> PASS ---
out=$(run_case apparmor-enabled "" present Y)
assert_check "$out" mac_backend PASS "apparmor:enabled"

# --- AppArmor: disabled (N) -> FAIL, not PASS (the false-green this fixes) ---
out=$(run_case apparmor-disabled "" present N)
assert_check "$out" mac_backend FAIL "apparmor:disabled"

# --- AppArmor: unexpected parameter value -> UNKNOWN, never PASS/FAIL ---
out=$(run_case apparmor-unexpected "" present "?")
assert_check "$out" mac_backend UNKNOWN "apparmor:unexpected-value:?"

# --- AppArmor: sysfs parameter unreadable, aa-status fallback enabled -> PASS ---
out=$(run_case apparmor-fallback-enabled "" absent "" enabled)
assert_check "$out" mac_backend PASS "apparmor:enabled"

# --- AppArmor: sysfs parameter unreadable, aa-status fallback disabled -> FAIL ---
out=$(run_case apparmor-fallback-disabled "" absent "" disabled)
assert_check "$out" mac_backend FAIL "apparmor:disabled"

# --- Neither SELinux nor AppArmor tooling present -> UNKNOWN ---
out=$(run_case no-mac-tooling "" absent "" absent)
assert_check "$out" mac_backend UNKNOWN no-selinux-or-apparmor

echo "node-storage-mac-backend-test.sh: all scenarios passed"
