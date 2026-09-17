#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT
CONTRACT="$TMPDIR_TEST/contracts.json"
OUTPUT="$TMPDIR_TEST/status.json"
RELEASE_EVIDENCE="$TMPDIR_TEST/release"

printf '%s\n' '{"schema":"kube-ready-contracts/v1","reports":[{"name":"readiness"},{"name":"security"},{"name":"license"}]}' > "$CONTRACT"
CONTRACT="$CONTRACT" RELEASE_EVIDENCE="$RELEASE_EVIDENCE" OUTPUT="$OUTPUT" REVISION=test-revision bash "$ROOT/tools/openforge-project-status.sh" >/dev/null
python3 - "$OUTPUT" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
by_id = data["capabilities"]
assert set(by_id) == {"node-readiness", "workload-security", "license-gate"}
assert all(capability["status"] == "verifying" for capability in by_id.values())
assert all(capability["verification"]["unit"] == "not-run" for capability in by_id.values())
assert all(capability["verification"]["runtime"] == "not-run" for capability in by_id.values())
assert by_id["node-readiness"]["verification"]["security"] == "not-applicable"
assert by_id["workload-security"]["verification"]["security"] == "not-run"
assert by_id["license-gate"]["verification"]["security"] == "not-run"
assert by_id["workload-security"]["standard"] == "openforge/agent-execution-security"
assert data["development"] == {"status": "active", "milestone": None, "progress_percent": None}
assert data["evidence"]["runtime"] == "not-run"
assert data["version"] == "openforge-project-status/v1"
assert data["updated_at"].count("-") == 2
PY

mkdir -p "$RELEASE_EVIDENCE/2026-09-06" "$RELEASE_EVIDENCE/2026-09-07"
printf '%s\n' '{"capability":"workload-security","status":"FAIL"}' > "$RELEASE_EVIDENCE/2026-09-06/workload-security.json"
printf '%s\n' '{"capability":"workload-security","status":"PASS"}' > "$RELEASE_EVIDENCE/2026-09-07/workload-security.json"
CONTRACT="$CONTRACT" RELEASE_EVIDENCE="$RELEASE_EVIDENCE" OUTPUT="$OUTPUT" REVISION=test-revision bash "$ROOT/tools/openforge-project-status.sh" >/dev/null
python3 - "$OUTPUT" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["capabilities"]["workload-security"]["status"] == "implemented"
assert data["capabilities"]["workload-security"]["verification"]["runtime"] == "pass"
assert data["evidence"]["runtime"] == "pass"
PY

python3 - "$OUTPUT" "$TMPDIR_TEST" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1], encoding="utf-8"))
root = sys.argv[2]
for name, mutate in {
    "array-capabilities": lambda value: value.__setitem__("capabilities", []),
    "unknown-top-level": lambda value: value.__setitem__("unknown", True),
    "bad-repository": lambda value: value.__setitem__("repository", "dasomel"),
}.items():
    value = json.loads(json.dumps(payload))
    mutate(value)
    with open(f"{root}/{name}.json", "w", encoding="utf-8") as handle:
        json.dump(value, handle)
PY
for case in array-capabilities unknown-top-level bad-repository; do
  if CONTRACT="$CONTRACT" RELEASE_EVIDENCE="$RELEASE_EVIDENCE" OUTPUT="$OUTPUT" REVISION=test-revision \
    VALIDATE_PAYLOAD="$TMPDIR_TEST/$case.json" \
    bash "$ROOT/tools/openforge-project-status.sh" >/dev/null 2>&1; then
    echo "expected schema rejection for $case" >&2
    exit 1
  fi
  if CONTRACT="$CONTRACT" RELEASE_EVIDENCE="$RELEASE_EVIDENCE" OUTPUT="$OUTPUT" REVISION=test-revision \
    VALIDATE_PAYLOAD="$TMPDIR_TEST/$case.json" OPENFORGE_FORCE_FALLBACK_VALIDATOR=1 \
    bash "$ROOT/tools/openforge-project-status.sh" >/dev/null 2>&1; then
    echo "expected schema rejection for $case" >&2
    exit 1
  fi
done

echo "openforge project status tests: PASS"
