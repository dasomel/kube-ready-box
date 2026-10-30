#!/usr/bin/env bash
set -euo pipefail
BOX="${1:-/etc/vagrant-box/info.json}"
READINESS="${2:-/etc/vagrant-box/node-readiness.json}"
OUT="${3:-/etc/vagrant-box/node-readiness-manifest.json}"

[ -s "$READINESS" ] || { echo "missing readiness report: $READINESS" >&2; exit 2; }
SUMS="$(mktemp)"
trap 'rm -f "$SUMS"' EXIT
sha256sum "$BOX" "$READINESS" > "$SUMS"
box_digest=$(awk -v f="$BOX" '$2==f {print $1}' "$SUMS")
readiness_digest=$(awk -v f="$READINESS" '$2==f {print $1}' "$SUMS")
version=$(python3 - "$BOX" <<'PY'
import json,sys
try:
 x=json.load(open(sys.argv[1])); v=x.get('version')
 print(v if isinstance(v,str) and v else 'UNKNOWN')
except Exception: print('UNKNOWN')
PY
)
[ "$version" != "UNKNOWN" ] || echo "warning: box version unreadable in $BOX (recorded as UNKNOWN)" >&2
validator_version="node-readiness-attest-v1"
cat > "$OUT" <<EOF
{"schema":"kube-ready-readiness/v1","kind":"immutable-node-readiness-manifest","box":{"path":"$BOX","version":"$version","sha256":"$box_digest"},"readiness":{"path":"$READINESS","sha256":"$readiness_digest"},"validator":"$validator_version"}
EOF
cat "$OUT"
