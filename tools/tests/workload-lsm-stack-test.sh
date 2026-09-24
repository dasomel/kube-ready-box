#!/usr/bin/env bash
# Deterministic fixture coverage for #44 T-012 (REQ-003, AC-003): the
# `lsm_stack` check in security/workload-security-check.sh must be additive
# only -- readable+non-empty -> PASS with the raw list, absent/unreadable ->
# UNKNOWN with an enumerated reason -- and must never FAIL or change any
# other check's status/count. The production script has no env override for
# the securityfs path (D7: no production-settable evidence-source bypass),
# so this drives the allow/deny cases via a PATH-shimmed `cat`: a wrapper
# that answers only the literal `cat /sys/kernel/security/lsm` call with
# fixture content/errors and passes every other invocation through to the
# real `cat` -- the same PATH-shim pattern as
# tools/tests/network-firewall-detection-test.sh. Must pass on both macOS
# and Linux.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/security/workload-security-check.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

real_cat=$(command -v cat)

# write_lsm_cat_shim <bindir> <mode> <content>
# mode: present (fixture content), absent (No such file or directory),
# permission-denied (Permission denied). Any other `cat` invocation is
# passed through to the real binary unchanged.
write_lsm_cat_shim() {
  local bindir=$1 mode=$2 content=$3
  mkdir -p "$bindir"
  cat > "$bindir/cat" <<SHIM
#!/usr/bin/env bash
set -euo pipefail
if [ "\$#" -eq 1 ] && [ "\$1" = "/sys/kernel/security/lsm" ]; then
  case "$mode" in
    present)
      printf '%s\n' "$content"
      exit 0
      ;;
    permission-denied)
      echo "cat: /sys/kernel/security/lsm: Permission denied" >&2
      exit 1
      ;;
    absent)
      echo "cat: /sys/kernel/security/lsm: No such file or directory" >&2
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

# assert_other_checks_unchanged <baseline.json> <candidate.json>
# Every check id other than lsm_stack keeps the same status, and the
# failures/unknowns counts and overall status match -- proof that
# lsm_stack is additive-only and never flips another check or the overall
# status/exit code.
assert_other_checks_unchanged() {
  local baseline=$1 candidate=$2
  python3 - "$baseline" "$candidate" <<'PY'
import json, sys
baseline_path, candidate_path = sys.argv[1:]
baseline = json.load(open(baseline_path, encoding="utf-8"))
candidate = json.load(open(candidate_path, encoding="utf-8"))

def by_id(doc):
    return {c["id"]: c["status"] for c in doc["checks"] if c["id"] != "lsm_stack"}

b, c = by_id(baseline), by_id(candidate)
if b != c:
    print(f"::error::non-lsm_stack checks changed between runs: {b} != {c}")
    raise SystemExit(1)
if baseline["failures"] != candidate["failures"]:
    print(f"::error::failures count changed: {baseline['failures']} != {candidate['failures']}")
    raise SystemExit(1)
if baseline["status"] != candidate["status"]:
    print(f"::error::overall status changed: {baseline['status']} != {candidate['status']}")
    raise SystemExit(1)
PY
}

run_case() {
  local name=$1 mode=$2 content=$3
  local bindir="$WORKDIR/bin-$name"
  write_lsm_cat_shim "$bindir" "$mode" "$content"
  local out="$WORKDIR/$name.json"
  set +e
  PATH="$bindir:$PATH" bash "$SCRIPT" >"$out" 2>"$WORKDIR/$name.stderr"
  set -e
  python3 -m json.tool "$out" >/dev/null || {
    echo "::error::$name did not produce parseable JSON" >&2
    cat "$WORKDIR/$name.stderr" >&2
    exit 1
  }
  echo "$out"
}

# --- allow: securityfs readable and non-empty -> PASS with the raw list ---
allow_out=$(run_case lsm-enabled present "lockdown,capability,landlock,yama,apparmor,integrity")
assert_check "$allow_out" lsm_stack PASS "lockdown,capability,landlock,yama,apparmor,integrity"

# --- deny: securityfs path absent -> UNKNOWN securityfs-absent, never FAIL ---
deny_out=$(run_case lsm-absent absent "")
assert_check "$deny_out" lsm_stack UNKNOWN securityfs-absent

# lsm_stack must never contribute a FAIL, and adding/removing it must not
# change any other check's status or the overall status/exit code.
assert_other_checks_unchanged "$allow_out" "$deny_out"

# --- deny: path exists but is unreadable -> UNKNOWN permission-denied ---
unreadable_out=$(run_case lsm-unreadable permission-denied "")
assert_check "$unreadable_out" lsm_stack UNKNOWN permission-denied
assert_other_checks_unchanged "$allow_out" "$unreadable_out"

# --- deny: readable but empty -> UNKNOWN empty-stack, not permission-denied ---
empty_out=$(run_case lsm-empty present "")
assert_check "$empty_out" lsm_stack UNKNOWN empty-stack
assert_other_checks_unchanged "$allow_out" "$empty_out"

echo "workload-lsm-stack-test.sh: all scenarios passed"
