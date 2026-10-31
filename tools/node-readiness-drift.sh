#!/usr/bin/env bash
set -euo pipefail
BASELINE="${1:-/etc/vagrant-box/node-readiness.json}"
CURRENT="${2:-/tmp/node-readiness-current.json}"

[ -s "$BASELINE" ] || { echo "missing baseline: $BASELINE" >&2; exit 2; }
ATTEST="${READINESS_ATTEST_SCRIPT:-$(dirname "$0")/node-readiness-attest.sh}"

# 이전 실행의 stale CURRENT가 비교 대상이 되면 거짓 NO_DRIFT가 나온다 -> 먼저 제거
rm -f "$CURRENT"
# attest 종료 코드는 readiness FAIL(정상 결과)을 반영하므로 무시하되, 결과 파일은 검증한다.
# 실행 비트에 의존하지 않도록 bash로 호출한다.
READINESS_OUTPUT="$CURRENT" STRICT_READINESS=0 bash "$ATTEST" >/dev/null || true

if [ ! -s "$CURRENT" ] || ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$CURRENT" 2>/dev/null; then
  echo "attest did not produce a valid JSON report: $CURRENT (script: $ATTEST)" >&2
  exit 2
fi

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
