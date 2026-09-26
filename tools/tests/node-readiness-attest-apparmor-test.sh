#!/usr/bin/env bash
# Deterministic fixture coverage for #44 T-021: tools/node-readiness-attest.sh's
# `apparmor` check must not PASS on bare `/sys/module/apparmor` directory
# existence -- it reads the kernel module parameter (Y/N) and a disabled
# module is FAIL, not the previous false PASS-on-existence. Runs the real
# script with a PATH-shimmed `cat` answering only the literal
# `/sys/module/apparmor/parameters/enabled` read (D7: no production env-var
# bypass for the /sys path), the same technique as
# tools/tests/workload-lsm-stack-test.sh. Must pass on both macOS and Linux.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/tools/node-readiness-attest.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

real_cat=$(command -v cat)

# write_cat_shim <bindir> <mode> <value>
# mode: present (cat prints value) or absent (No such file or directory).
# Any other `cat` invocation passes through to the real binary unchanged.
write_cat_shim() {
  local bindir=$1 mode=$2 value=$3
  mkdir -p "$bindir"
  cat > "$bindir/cat" <<SHIM
#!/usr/bin/env bash
set -euo pipefail
if [ "\$#" -eq 1 ] && [ "\$1" = "/sys/module/apparmor/parameters/enabled" ]; then
  case "$mode" in
    present)
      printf '%s\n' "$value"
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

run_case() {
  local name=$1 mode=$2 value=$3
  local bindir="$WORKDIR/bin-$name"
  write_cat_shim "$bindir" "$mode" "$value"
  local out="$WORKDIR/$name.json"
  set +e
  PATH="$bindir:$PATH" READINESS_OUTPUT="$out" bash "$SCRIPT" >"$WORKDIR/$name.stdout" 2>"$WORKDIR/$name.stderr"
  set -e
  python3 -m json.tool "$out" >/dev/null || {
    echo "::error::$name did not produce parseable JSON" >&2
    cat "$WORKDIR/$name.stderr" >&2
    exit 1
  }
  echo "$out"
}

# --- allow: enabled (Y) -> PASS ---
out=$(run_case apparmor-enabled present Y)
assert_check "$out" apparmor PASS enabled

# --- deny: disabled (N) -> FAIL, not PASS on bare directory existence ---
out=$(run_case apparmor-disabled present N)
assert_check "$out" apparmor FAIL disabled

# --- deny: unexpected parameter value -> UNKNOWN, never PASS/FAIL ---
out=$(run_case apparmor-unexpected present "?")
assert_check "$out" apparmor UNKNOWN "unexpected-value:?"

# --- deny: parameter unreadable (module absent/kernel lacks AppArmor) -> UNKNOWN ---
out=$(run_case apparmor-unreadable absent "")
assert_check "$out" apparmor UNKNOWN not-loaded

echo "node-readiness-attest-apparmor-test.sh: all scenarios passed"
