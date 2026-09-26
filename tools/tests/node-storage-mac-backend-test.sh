#!/usr/bin/env bash
# Deterministic fixture coverage for #44 T-021 (REQ-003, AC-003, AC-004,
# D4): storage/node-storage-readiness.sh's `mac_backend` check must not PASS
# for a disabled AppArmor or a permissive/disabled SELinux (the false-green
# fixed here: "PASS apparmor:disabled" and "PASS selinux:Permissive"), and
# it must route to the native LSM by OS family (ID, then ID_LIKE) -- never
# by which tool (getenforce/aa-status) happens to be on PATH (a Codex
# terra-high review of an earlier revision caught this: an AppArmor-native
# host with a stray getenforce binary previously misreported SELinux, and
# vice versa). It must also never fall back to a PASS/FAIL guess from
# aa-status's mere presence when the AppArmor sysfs parameter itself is
# unreadable -- that stays UNKNOWN.
#
# Runs a temporary copy of the real validator with only /etc/os-release
# redirected to a fixture (same technique as
# tools/tests/workload-security-classification-test.sh), so all
# classification/status logic stays production code. PATH is an isolated
# symlink farm of only the real utilities the script unconditionally needs
# (python3 for every add() call, plus grep/cut/tr/df/awk/tail/head for the
# checks ahead of mac_backend), so no real getenforce/aa-status on the test
# host can leak into a scenario; the AppArmor sysfs read is shimmed the way
# tools/tests/workload-lsm-stack-test.sh shims `cat` (D7: no production
# env-var bypass for the /sys path). Must pass on both macOS and Linux.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

sed -e "s|/etc/os-release|$WORKDIR/os-release|g" \
  "$ROOT/storage/node-storage-readiness.sh" > "$WORKDIR/node-storage-readiness.sh"
chmod +x "$WORKDIR/node-storage-readiness.sh"

essentials_dir="$WORKDIR/essentials"
mkdir -p "$essentials_dir"
for tool in bash python3 grep cut tr df awk printf tail head; do
  real=$(command -v "$tool" 2>/dev/null || true)
  [ -n "$real" ] && ln -sf "$real" "$essentials_dir/$tool"
done

write_os_release() {
  printf 'ID="%s"\nID_LIKE="%s"\n' "$1" "$2" > "$WORKDIR/os-release"
}

# write_scenario_bin <bindir> [selinux_state] [apparmor_mode] [apparmor_value]
# selinux_state: unset (no getenforce shim, i.e. no getenforce binary at
# all) or a getenforce stdout value (Enforcing/Permissive/Disabled/<other>).
# apparmor_mode: absent (cat errors: No such file or directory) or present
# (cat prints apparmor_value).
write_scenario_bin() {
  local bindir=$1 selinux_state=${2:-} apparmor_mode=${3:-absent} apparmor_value=${4:-}
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

# run_case <name> <id> <id_like> [selinux_state] [apparmor_mode] [apparmor_value]
run_case() {
  local name=$1 id=$2 id_like=$3
  shift 3
  local bindir="$WORKDIR/bin-$name"
  write_scenario_bin "$bindir" "$@"
  write_os_release "$id" "$id_like"
  local out="$WORKDIR/$name.json"
  set +e
  PATH="$bindir" bash "$WORKDIR/node-storage-readiness.sh" >"$out" 2>"$WORKDIR/$name.stderr"
  set -e
  python3 -m json.tool "$out" >/dev/null || {
    echo "::error::$name did not produce parseable JSON" >&2
    cat "$WORKDIR/$name.stderr" >&2
    exit 1
  }
  echo "$out"
}

# --- AppArmor family (ubuntu): enabled (Y) -> PASS ---
out=$(run_case apparmor-enabled ubuntu '' '' present Y)
assert_check "$out" mac_backend PASS "apparmor:enabled"

# --- AppArmor family: disabled (N) -> FAIL, not PASS (the false-green this fixes) ---
out=$(run_case apparmor-disabled ubuntu '' '' present N)
assert_check "$out" mac_backend FAIL "apparmor:disabled"

# --- AppArmor family: unexpected parameter value -> UNKNOWN, never PASS/FAIL ---
out=$(run_case apparmor-unexpected ubuntu '' '' present "?")
assert_check "$out" mac_backend UNKNOWN "apparmor:unexpected-value:?"

# --- AppArmor family: sysfs parameter unreadable -> UNKNOWN, never a PASS/FAIL
# guess from aa-status's mere presence (no aa-status fallback exists anymore). ---
out=$(run_case apparmor-unreadable ubuntu '' '' absent)
assert_check "$out" mac_backend UNKNOWN "apparmor:parameters-unreadable"

# --- Regression for the tool-presence routing bug: an AppArmor-native host
# (debian, via ID_LIKE) with a stray getenforce binary on PATH must still
# route to AppArmor, not SELinux. ---
out=$(run_case apparmor-family-ignores-stray-getenforce custom debian Enforcing present N)
assert_check "$out" mac_backend FAIL "apparmor:disabled"

# --- SELinux family (rocky): Enforcing -> PASS ---
out=$(run_case selinux-enforcing rocky '' Enforcing)
assert_check "$out" mac_backend PASS "selinux:Enforcing"

# --- SELinux family: Permissive -> FAIL, not PASS (the false-green this fixes) ---
out=$(run_case selinux-permissive rocky '' Permissive)
assert_check "$out" mac_backend FAIL "selinux:Permissive"

# --- SELinux family: Disabled -> FAIL ---
out=$(run_case selinux-disabled rocky '' Disabled)
assert_check "$out" mac_backend FAIL "selinux:Disabled"

# --- SELinux family: unexpected getenforce output -> UNKNOWN, never PASS/FAIL ---
out=$(run_case selinux-unexpected rocky '' garbled)
assert_check "$out" mac_backend UNKNOWN "selinux:garbled"

# --- Regression for the tool-presence routing bug, reversed: a SELinux-native
# host (alma, via ID_LIKE) with the AppArmor sysfs parameter readable must
# still route to SELinux, not AppArmor. ---
out=$(run_case selinux-family-ignores-apparmor-sysfs custom almalinux Permissive present Y)
assert_check "$out" mac_backend FAIL "selinux:Permissive"

# --- Unrecognized OS family -> UNKNOWN, never healthy ---
out=$(run_case family-unknown unknown '')
assert_check "$out" mac_backend UNKNOWN unknown

echo "node-storage-mac-backend-test.sh: all scenarios passed"
