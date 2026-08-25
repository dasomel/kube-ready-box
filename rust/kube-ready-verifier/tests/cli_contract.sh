#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# CI는 --release 만 빌드하므로 debug 경로를 고정하면 바이너리를 못 찾는다.
# BIN 으로 직접 지정할 수 있게 두고, 없으면 release -> debug 순으로 찾는다.
BIN="${BIN:-}"
if [ -z "$BIN" ]; then
  for candidate in "$ROOT/target/release/kube-ready-verifier" "$ROOT/target/debug/kube-ready-verifier"; do
    if [ -x "$candidate" ]; then BIN="$candidate"; break; fi
  done
fi
[ -n "$BIN" ] && [ -x "$BIN" ] || {
  echo "kube-ready-verifier 바이너리를 찾지 못했습니다. 먼저 cargo build 하세요." >&2
  echo "  찾은 경로: $ROOT/target/{release,debug}/kube-ready-verifier" >&2
  exit 1
}
echo "Using binary: $BIN"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

"$BIN" --help >/dev/null

# --- preflight: default vs --strict-runtime ---------------------------------
"$BIN" preflight > "$WORK/preflight.json" || rc=$?
rc=${rc:-0}
test "$rc" -eq 0 -o "$rc" -eq 1
python3 - <<'PY' "$WORK/preflight.json"
import json, sys
x = json.load(open(sys.argv[1]))
assert x["schema"] == "kube-ready-evidence/v1"
assert x["kind"] == "node-preflight"
assert x["status"] in ("PASS", "FAIL")
assert isinstance(x["checks"], list)
PY

"$BIN" preflight --strict-runtime > "$WORK/preflight-strict.json" || rc=$?
rc=${rc:-0}
test "$rc" -eq 0 -o "$rc" -eq 1
python3 - <<'PY' "$WORK/preflight.json" "$WORK/preflight-strict.json"
import json, sys
plain = json.load(open(sys.argv[1]))
strict = json.load(open(sys.argv[2]))
plain_containerd = next(c for c in plain["checks"] if c["id"] == "containerd")
strict_containerd = next(c for c in strict["checks"] if c["id"] == "containerd")
# --strict-runtime only escalates an UNKNOWN containerd result to FAIL --
# a host with containerd already installed sees no divergence, which is
# expected (not a bug): assert the *rule*, not a specific outcome.
if plain_containerd["status"] == "UNKNOWN":
    assert strict_containerd["status"] == "FAIL", "strict-runtime must escalate UNKNOWN containerd to FAIL"
else:
    assert strict_containerd["status"] == plain_containerd["status"]
PY
echo "preflight --strict-runtime divergence rule: PASS"

# --- verify-sha256: happy path ----------------------------------------------
printf '%s  %s\n' "$(printf test | sha256sum | cut -d' ' -f1)" "$WORK/payload" > "$WORK/manifest.good"
printf test > "$WORK/payload"
"$BIN" verify-sha256 "$WORK/manifest.good"

# --- verify-sha256: missing manifest -> exit 2 ------------------------------
set +e
"$BIN" verify-sha256 "$WORK/does-not-exist" >/dev/null 2>"$WORK/missing.err"
rc=$?
set -e
test "$rc" -eq 2
echo "verify-sha256 missing manifest exit 2: PASS"

# --- verify-sha256: empty manifest -> PASS, checked/failures/malformed=0 ---
: > "$WORK/manifest.empty"
"$BIN" verify-sha256 "$WORK/manifest.empty" > "$WORK/empty.json"
python3 - <<'PY' "$WORK/empty.json"
import json, sys
x = json.load(open(sys.argv[1]))
assert x["status"] == "PASS"
assert x["checked"] == 0
assert x["failures"] == 0
assert x["malformed"] == 0
PY
echo "verify-sha256 empty manifest: PASS"

# --- verify-sha256: malformed line mixed with a valid one -> FAIL, exit 1 --
{
  printf '%s  %s\n' "$(printf test | sha256sum | cut -d' ' -f1)" "$WORK/payload"
  printf 'not-a-valid-manifest-line\n'
} > "$WORK/manifest.malformed"
set +e
"$BIN" verify-sha256 "$WORK/manifest.malformed" > "$WORK/malformed.json"
rc=$?
set -e
test "$rc" -eq 1
python3 - <<'PY' "$WORK/malformed.json"
import json, sys
x = json.load(open(sys.argv[1]))
assert x["status"] == "FAIL"
assert x["malformed"] == 1
PY
echo "verify-sha256 malformed line forces FAIL: PASS"

# --- verify-evidence: missing release dir -> all 5 files FAIL/missing ------
mkdir -p "$WORK/evidence-missing"
set +e
"$BIN" verify-evidence "$WORK/evidence-missing" > "$WORK/evidence-missing.json"
rc=$?
set -e
test "$rc" -eq 1
python3 - <<'PY' "$WORK/evidence-missing.json"
import json, sys
x = json.load(open(sys.argv[1]))
assert x["schema"] == "kube-ready-evidence/v1"
assert x["kind"] == "release-evidence-verification"
assert x["status"] == "FAIL"
assert x["failures"] == 5
for c in x["checks"]:
    assert c["status"] == "FAIL"
    assert c["detail"] == "missing"
PY
echo "verify-evidence missing release dir: PASS"

# --- verify-evidence: truncated SHA256SUMS -> that one file FAILs ----------
mkdir -p "$WORK/evidence-truncated"
printf '{}' > "$WORK/evidence-truncated/verification.json"
printf 'deadbeef  a.txt\n' > "$WORK/evidence-truncated/SHA256SUMS"
printf '{}' > "$WORK/evidence-truncated/sbom.json"
printf '{}' > "$WORK/evidence-truncated/security-report.json"
printf '{}' > "$WORK/evidence-truncated/license-report.json"
set +e
"$BIN" verify-evidence "$WORK/evidence-truncated" > "$WORK/evidence-truncated.json"
rc=$?
set -e
test "$rc" -eq 1
python3 - <<'PY' "$WORK/evidence-truncated.json"
import json, sys
x = json.load(open(sys.argv[1]))
assert x["status"] == "FAIL"
assert x["failures"] == 1
sha = next(c for c in x["checks"] if c["id"] == "SHA256SUMS")
assert sha["status"] == "FAIL"
for name in ("verification.json", "sbom.json", "security-report.json", "license-report.json"):
    c = next(c for c in x["checks"] if c["id"] == name)
    assert c["status"] == "PASS", f"{name}: {c}"
PY
echo "verify-evidence truncated SHA256SUMS isolates the one bad file: PASS"

# --- verify-evidence: fully valid fixture -> PASS, exit 0 ------------------
mkdir -p "$WORK/evidence-valid"
printf '{}' > "$WORK/evidence-valid/verification.json"
digest=$(printf test | sha256sum | cut -d' ' -f1)
printf '%s  a.txt\n' "$digest" > "$WORK/evidence-valid/SHA256SUMS"
printf '{}' > "$WORK/evidence-valid/sbom.json"
printf '{}' > "$WORK/evidence-valid/security-report.json"
printf '{}' > "$WORK/evidence-valid/license-report.json"
"$BIN" verify-evidence "$WORK/evidence-valid" > "$WORK/evidence-valid.json"
python3 - <<'PY' "$WORK/evidence-valid.json"
import json, sys
x = json.load(open(sys.argv[1]))
assert x["status"] == "PASS"
assert x["failures"] == 0
PY
echo "verify-evidence valid fixture: PASS"

echo "Rust CLI contract: PASS"
