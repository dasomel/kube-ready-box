#!/usr/bin/env bash
set -euo pipefail
BASELINE="${1:-/etc/vagrant-box/node-readiness.json}"
CURRENT="${2:-/tmp/node-readiness-current.json}"

[ -s "$BASELINE" ] || { echo "missing baseline: $BASELINE" >&2; exit 2; }
READINESS_OUTPUT="$CURRENT" STRICT_READINESS=0 "$(dirname "$0")/node-readiness-attest.sh" >/dev/null || true

python3 - "$BASELINE" "$CURRENT" <<'PY'
import json,sys
base=json.load(open(sys.argv[1])); cur=json.load(open(sys.argv[2]))
ignore={'failures','unknowns'}
def normalized(x):
    return {k:v for k,v in x.items() if k not in ignore}
if normalized(base)==normalized(cur):
    print('{"schema":"kube-ready-readiness/v1","status":"NO_DRIFT","changed":[]}')
    raise SystemExit(0)
base_checks={x['id']:x for x in base.get('checks',[])}
cur_checks={x['id']:x for x in cur.get('checks',[])}
changed=[]
for key in sorted(set(base_checks)|set(cur_checks)):
    if base_checks.get(key)!=cur_checks.get(key): changed.append(key)
print('{"schema":"kube-ready-readiness/v1","status":"DRIFT","changed":'+json.dumps(changed,separators=(',',':'))+'}')
raise SystemExit(1)
PY
