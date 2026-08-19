#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/target/debug/kube-ready-verifier"

test -x "$BIN"
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
