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
"$BIN" --help >/dev/null
"$BIN" preflight > /tmp/kube-ready-preflight.json || rc=$?
rc=${rc:-0}
test "$rc" -eq 0 -o "$rc" -eq 1
python3 - <<'PY' /tmp/kube-ready-preflight.json
import json,sys
x=json.load(open(sys.argv[1]))
assert x["schema"] == "kube-ready-evidence/v1"
assert x["kind"] == "node-preflight"
assert x["status"] in ("PASS", "FAIL")
assert isinstance(x["checks"], list)
PY

tmp=$(mktemp)
printf '%s  %s\n' "$(printf test | sha256sum | cut -d' ' -f1)" "$tmp.payload" > "$tmp.manifest"
printf test > "$tmp.payload"
"$BIN" verify-sha256 "$tmp.manifest"
rm -f "$tmp.manifest" "$tmp.payload"

echo "Rust CLI contract: PASS"
