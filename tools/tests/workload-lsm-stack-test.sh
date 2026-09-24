#!/usr/bin/env bash
# Deterministic fixture coverage for #44 T-012 (REQ-003, AC-003): the
# `lsm_stack` check in security/workload-security-check.sh must be additive
# only -- readable+non-empty -> PASS with the raw list, absent/unreadable ->
# UNKNOWN with an enumerated reason -- and must never FAIL or change any
# other check's status/count. Drives the real script via
# KUBE_READY_LSM_STACK_PATH, a minimal override that defaults to the real
# kernel path (/sys/kernel/security/lsm) and only redirects the securityfs
# read for this one check; it does not toggle or bypass any security
# control. Must pass on both macOS and Linux.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/security/workload-security-check.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

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
# failures/unknowns counts (minus lsm_stack's own UNKNOWN contribution,
# which is always 0 since it never counts as a failure) match -- proof
# that lsm_stack is additive-only and never flips another check or the
# overall status/exit code.
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
  local name=$1 lsm_path=$2
  local out="$WORKDIR/$name.json"
  set +e
  KUBE_READY_LSM_STACK_PATH="$lsm_path" bash "$SCRIPT" >"$out" 2>"$WORKDIR/$name.stderr"
  set -e
  python3 -m json.tool "$out" >/dev/null || {
    echo "::error::$name did not produce parseable JSON" >&2
    cat "$WORKDIR/$name.stderr" >&2
    exit 1
  }
  echo "$out"
}

# --- allow: securityfs readable and non-empty -> PASS with the raw list ---
lsm_fixture="$WORKDIR/lsm-enabled"
printf 'lockdown,capability,landlock,yama,apparmor,integrity\n' > "$lsm_fixture"
allow_out=$(run_case lsm-enabled "$lsm_fixture")
assert_check "$allow_out" lsm_stack PASS "lockdown,capability,landlock,yama,apparmor,integrity"

# --- deny: securityfs path absent -> UNKNOWN securityfs-absent, never FAIL ---
deny_out=$(run_case lsm-absent "$WORKDIR/does-not-exist")
assert_check "$deny_out" lsm_stack UNKNOWN securityfs-absent

# lsm_stack must never contribute a FAIL, and adding/removing it must not
# change any other check's status or the overall status/exit code.
assert_other_checks_unchanged "$allow_out" "$deny_out"

# --- deny: path exists but is unreadable -> UNKNOWN permission-denied ---
# Skipped when running as root (e.g. inside a Docker container by default),
# since root bypasses file-mode read permission and the case cannot be
# reproduced deterministically there.
if [ "$(id -u)" != 0 ]; then
  unreadable_fixture="$WORKDIR/lsm-unreadable"
  printf 'apparmor\n' > "$unreadable_fixture"
  chmod 000 "$unreadable_fixture"
  unreadable_out=$(run_case lsm-unreadable "$unreadable_fixture")
  assert_check "$unreadable_out" lsm_stack UNKNOWN permission-denied
  assert_other_checks_unchanged "$allow_out" "$unreadable_out"
else
  echo "workload-lsm-stack-test.sh: skipping permission-denied case (running as root)"
fi

echo "workload-lsm-stack-test.sh: all scenarios passed"
