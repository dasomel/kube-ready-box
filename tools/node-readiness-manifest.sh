#!/usr/bin/env bash
set -euo pipefail
BOX="${1:-/etc/vagrant-box/info.json}"
READINESS="${2:-/etc/vagrant-box/node-readiness.json}"
OUT="${3:-/etc/vagrant-box/node-readiness-manifest.json}"

[ -s "$READINESS" ] || { echo "missing readiness report: $READINESS" >&2; exit 2; }
sha256sum "$BOX" "$READINESS" > /tmp/node-readiness-sha256
box_digest=$(awk -v f="$BOX" '$2==f {print $1}' /tmp/node-readiness-sha256)
readiness_digest=$(awk -v f="$READINESS" '$2==f {print $1}' /tmp/node-readiness-sha256)
version=$(python3 - "$BOX" <<'PY'
import json,sys
try:
 x=json.load(open(sys.argv[1])); print(x.get('version','unknown'))
except Exception: print('unknown')
PY
)
validator_version="node-readiness-attest-v1"
cat > "$OUT" <<EOF
{"schema":"kube-ready-readiness/v1","kind":"immutable-node-readiness-manifest","box":{"path":"$BOX","version":"$version","sha256":"$box_digest"},"readiness":{"path":"$READINESS","sha256":"$readiness_digest"},"validator":"$validator_version"}
EOF
cat "$OUT"
rm -f /tmp/node-readiness-sha256
