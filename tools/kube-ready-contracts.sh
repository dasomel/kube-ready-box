#!/usr/bin/env bash
set -euo pipefail
OUT="${CONTRACT_OUTPUT:-/etc/vagrant-box/kube-ready-contracts.json}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$(dirname "$OUT")"
declare -a reports=()
run_report(){
  local name=$1 cmd=$2 tmp rc=0 last
  tmp=$(mktemp)
  if bash -c "$cmd" >"$tmp" 2>&1; then rc=0; else rc=$?; fi
  last=$(tail -n 1 "$tmp" || true)
  if python3 -c 'import json,sys; json.loads(sys.argv[1])' "$last" >/dev/null 2>&1; then reports+=("{\"name\":\"$name\",\"exit_code\":$rc,\"evidence\":$last}"); else reports+=("{\"name\":\"$name\",\"exit_code\":$rc,\"evidence\":null}"); fi
  rm -f "$tmp"
}
[ -f "$ROOT/tools/node-readiness-attest.sh" ] && run_report readiness "READINESS_OUTPUT=/tmp/readiness.json bash $ROOT/tools/node-readiness-attest.sh" || true
[ -f "$ROOT/network/node-network-readiness.sh" ] && run_report network "bash $ROOT/network/node-network-readiness.sh" || true
[ -f "$ROOT/storage/node-storage-readiness.sh" ] && run_report storage "bash $ROOT/storage/node-storage-readiness.sh" || true
[ -f "$ROOT/time/node-time-readiness.sh" ] && run_report time "bash $ROOT/time/node-time-readiness.sh" || true
[ -f "$ROOT/security/workload-security-check.sh" ] && run_report security "bash $ROOT/security/workload-security-check.sh" || true
[ -f "$ROOT/rocky/preflight.sh" ] && [ "${RUN_ROCKY_PROFILE:-0}" = 1 ] && run_report rocky "bash $ROOT/rocky/preflight.sh" || true
[ -f "$ROOT/nixos/preflight.sh" ] && [ "${RUN_NIXOS_PROFILE:-0}" = 1 ] && run_report nixos "bash $ROOT/nixos/preflight.sh" || true
python3 - "$OUT" "$(IFS=,; echo "${reports[*]:-}")" <<'PY'
import json,sys
out,raw=sys.argv[1:]
reports=json.loads('['+raw+']') if raw else []
obj={'schema':'kube-ready-contracts/v1','reports':reports,'offline':True}
open(out,'w').write(json.dumps(obj,sort_keys=True,separators=(',',':'))+'\n')
print(json.dumps(obj,sort_keys=True,separators=(',',':')))
PY
