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
printf '{"status":"PASS"}' > "$WORK/evidence-truncated/security-report.json"
printf '{"status":"PASS"}' > "$WORK/evidence-truncated/license-report.json"
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
printf test > "$WORK/evidence-valid/a.txt"
printf '%s  a.txt\n' "$digest" > "$WORK/evidence-valid/SHA256SUMS"
printf '{}' > "$WORK/evidence-valid/sbom.json"
printf '{"status":"PASS"}' > "$WORK/evidence-valid/security-report.json"
printf '{"status":"PASS"}' > "$WORK/evidence-valid/license-report.json"
"$BIN" verify-evidence "$WORK/evidence-valid" > "$WORK/evidence-valid.json"
python3 - <<'PY' "$WORK/evidence-valid.json"
import json, sys
x = json.load(open(sys.argv[1]))
assert x["status"] == "PASS"
assert x["failures"] == 0
PY
echo "verify-evidence valid fixture: PASS"

# --- verify-evidence: UNKNOWN 리포트는 FAIL, 명시적 opt-in 시에만 PASS -----
cp -R "$WORK/evidence-valid" "$WORK/evidence-unknown"
printf '{"status":"UNKNOWN"}' > "$WORK/evidence-unknown/security-report.json"
set +e
"$BIN" verify-evidence "$WORK/evidence-unknown" > "$WORK/evidence-unknown.json"
rc=$?
set -e
test "$rc" -eq 1
grep -q '"status":"FAIL"' "$WORK/evidence-unknown.json"
ALLOW_UNKNOWN_EVIDENCE=1 "$BIN" verify-evidence "$WORK/evidence-unknown" > "$WORK/evidence-unknown-ok.json"
grep -q '"failures":0' "$WORK/evidence-unknown-ok.json"
echo "verify-evidence UNKNOWN fails, passes only with ALLOW_UNKNOWN_EVIDENCE=1: PASS"

# --- verify-evidence: SHA256SUMS 의 '..'/절대경로 항목은 FAIL ---------------
cp -R "$WORK/evidence-valid" "$WORK/evidence-escape"
printf '%s  ../evidence-valid/a.txt\n' "$digest" > "$WORK/evidence-escape/SHA256SUMS"
set +e
"$BIN" verify-evidence "$WORK/evidence-escape" > "$WORK/evidence-escape.json"
rc=$?
set -e
test "$rc" -eq 1
grep -q 'escapes artifact dir' "$WORK/evidence-escape.json"
echo "verify-evidence SHA256SUMS path escape rejected: PASS"

# --- verify-evidence: 회귀 케이스(symlink 탈출/CRLF/status trim/빈 목록/'*' 마커/ARTIFACT_DIR) ---
expect_evidence_fail() {  # $1=label $2=dir
  set +e
  "$BIN" verify-evidence "$2" > "$2.json"
  local rc=$?
  set -e
  test "$rc" -eq 1 || { echo "$1: exit $rc (expected 1)" >&2; exit 1; }
}
mkdir -p "$WORK/outside"; printf test > "$WORK/outside/secret"
cp -R "$WORK/evidence-valid" "$WORK/evidence-flink"
ln -s "$WORK/outside/secret" "$WORK/evidence-flink/flink"
printf '%s  flink\n' "$digest" > "$WORK/evidence-flink/SHA256SUMS"
expect_evidence_fail "symlink file escape" "$WORK/evidence-flink"
grep -q 'escapes artifact dir' "$WORK/evidence-flink.json"
cp -R "$WORK/evidence-valid" "$WORK/evidence-dlink"
ln -s "$WORK/outside" "$WORK/evidence-dlink/dlink"
printf '%s  dlink/secret\n' "$digest" > "$WORK/evidence-dlink/SHA256SUMS"
expect_evidence_fail "symlink dir escape" "$WORK/evidence-dlink"
grep -q 'escapes artifact dir' "$WORK/evidence-dlink.json"
cp -R "$WORK/evidence-valid" "$WORK/evidence-crlf"
printf '%s  a.txt\r\n' "$digest" > "$WORK/evidence-crlf/SHA256SUMS"
expect_evidence_fail "CRLF" "$WORK/evidence-crlf"
cp -R "$WORK/evidence-valid" "$WORK/evidence-trim"
printf '{"status":" PASS "}' > "$WORK/evidence-trim/license-report.json"
expect_evidence_fail "status trim" "$WORK/evidence-trim"
cp -R "$WORK/evidence-valid" "$WORK/evidence-empty"
printf '  \n\n' > "$WORK/evidence-empty/SHA256SUMS"
expect_evidence_fail "empty SHA256SUMS" "$WORK/evidence-empty"
cp -R "$WORK/evidence-valid" "$WORK/evidence-star"
printf '%s *a.txt\n' "$digest" > "$WORK/evidence-star/SHA256SUMS"
"$BIN" verify-evidence "$WORK/evidence-star" | grep -q '"failures":0'
cp -R "$WORK/evidence-valid" "$WORK/evidence-artdir"
mkdir -p "$WORK/dist"; printf test > "$WORK/dist/k.box"
printf '%s  k.box\n' "$digest" > "$WORK/evidence-artdir/SHA256SUMS"
expect_evidence_fail "box missing without ARTIFACT_DIR" "$WORK/evidence-artdir"
grep -q 'ARTIFACT_DIR' "$WORK/evidence-artdir.json"
ARTIFACT_DIR="$WORK/dist" "$BIN" verify-evidence "$WORK/evidence-artdir" | grep -q '"failures":0'
echo "verify-evidence regression cases (symlink/CRLF/trim/empty/star/ARTIFACT_DIR): PASS"

# --- 사용법 오류: 잘못된 플래그/값은 조용히 무시되지 않고 exit 2 -----------
expect_usage_error() {
  local label="$1"; shift
  set +e
  "$BIN" "$@" >"$WORK/usage.out" 2>"$WORK/usage.err"
  local rc=$?
  set -e
  test "$rc" -eq 2 || { echo "$label: exit $rc (expected 2)" >&2; exit 1; }
  grep -q 'error:' "$WORK/usage.err" || { echo "$label: stderr 에 error 메시지 없음" >&2; exit 1; }
  echo "$label exit 2: PASS"
}
expect_usage_error "preflight bad --require-sandbox value" preflight --require-sandbox=gvisr
expect_usage_error "preflight unknown flag" preflight --strict-runtme
expect_usage_error "verify-sha256 unknown flag" verify-sha256 --bogus "$WORK/manifest.good"
expect_usage_error "verify-evidence unknown flag" verify-evidence --bogus "$WORK/evidence-valid"
# 유효한 호출은 그대로 동작 (exit 0 또는 1, 2 아님)
rc=0
"$BIN" preflight --require-sandbox=gvisor --strict-runtime >/dev/null 2>&1 || rc=$?
test "$rc" -eq 0 -o "$rc" -eq 1
echo "preflight valid flags still accepted: PASS"

echo "Rust CLI contract: PASS"
