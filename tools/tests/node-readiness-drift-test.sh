#!/usr/bin/env bash
# #13: node-readiness-drift.sh must never report NO_DRIFT from a stale CURRENT
# file or a failed attest run, and must not depend on the attest exec bit.
# READINESS_ATTEST_SCRIPT swaps in a stub; the manifest is covered when
# sha256sum exists (Linux).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DRIFT="$ROOT/tools/node-readiness-drift.sh"
MANIFEST="$ROOT/tools/node-readiness-manifest.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

BASE="$WORKDIR/base.json"
CUR="$WORKDIR/current.json"
REPORT='{"schema":"kube-ready-readiness/v1","checks":[{"id":"a","status":"PASS"},{"id":"b","status":"PASS"}],"failures":[],"unknowns":[]}'
echo "$REPORT" > "$BASE"

# stub는 의도적으로 실행 비트 없이 만든다 (bash로 호출되는지 확인)
write_stub() { printf '%s\n' "$1" > "$WORKDIR/stub.sh"; chmod 644 "$WORKDIR/stub.sh"; }
run_drift() {
  set +e
  READINESS_ATTEST_SCRIPT="$WORKDIR/stub.sh" bash "$DRIFT" "$BASE" "$CUR" >"$WORKDIR/out.log" 2>"$WORKDIR/err.log"
  rc=$?
  set -e
}

# 1. identical report -> NO_DRIFT
write_stub "printf '%s' '$REPORT' > \"\$READINESS_OUTPUT\""
run_drift
[ "$rc" = 0 ] && grep -q '"status":"NO_DRIFT"' "$WORKDIR/out.log" || fail "identical: rc=$rc $(cat "$WORKDIR/out.log")"

# 2. changed check -> DRIFT rc=1 naming the check; attest rc!=0 is tolerated
CHANGED='{"schema":"kube-ready-readiness/v1","checks":[{"id":"a","status":"PASS"},{"id":"b","status":"FAIL"}],"failures":["b"],"unknowns":[]}'
write_stub "printf '%s' '$CHANGED' > \"\$READINESS_OUTPUT\"; exit 1"
run_drift
[ "$rc" = 1 ] && grep -q '"status":"DRIFT"' "$WORKDIR/out.log" && grep -q '"changed":\["b"\]' "$WORKDIR/out.log" || fail "changed: rc=$rc $(cat "$WORKDIR/out.log")"

# 3. crashing stub + stale identical CURRENT -> exit 2, never NO_DRIFT
echo "$REPORT" > "$CUR"
write_stub 'exit 127'
run_drift
[ "$rc" = 2 ] || fail "crash+stale: rc=$rc"
grep -q NO_DRIFT "$WORKDIR/out.log" && fail "crash+stale printed NO_DRIFT"
[ -s "$WORKDIR/err.log" ] || fail "crash+stale: no stderr message"

# 4. stub writing non-JSON -> exit 2
write_stub "echo garbage > \"\$READINESS_OUTPUT\""
run_drift
[ "$rc" = 2 ] || fail "non-json: rc=$rc"

# 5. missing baseline -> exit 2
set +e; READINESS_ATTEST_SCRIPT="$WORKDIR/stub.sh" bash "$DRIFT" "$WORKDIR/none.json" "$CUR" >/dev/null 2>&1; rc=$?; set -e
[ "$rc" = 2 ] || fail "missing baseline: rc=$rc"

# 6. manifest: unreadable info.json -> explicit UNKNOWN; readable -> real version
if command -v sha256sum >/dev/null 2>&1; then
  echo "not json" > "$WORKDIR/info.json"
  bash "$MANIFEST" "$WORKDIR/info.json" "$BASE" "$WORKDIR/m.json" >/dev/null 2>&1
  grep -q '"version":"UNKNOWN"' "$WORKDIR/m.json" || fail "manifest bad info: $(cat "$WORKDIR/m.json")"
  echo '{"version":"1.2.3"}' > "$WORKDIR/info.json"
  bash "$MANIFEST" "$WORKDIR/info.json" "$BASE" "$WORKDIR/m.json" >/dev/null 2>&1
  grep -q '"version":"1.2.3"' "$WORKDIR/m.json" || fail "manifest good info"
else
  echo "node-readiness-drift-test: sha256sum missing, manifest scenario skipped" >&2
fi

echo "node-readiness-drift-test: all scenarios passed"
