#!/usr/bin/env bash
set -euo pipefail
OUT="${CONTRACT_OUTPUT:-/etc/vagrant-box/kube-ready-contracts.json}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$(dirname "$OUT")"
declare -a reports=()
# 증거를 못 만든 리포트 이름. 스크립트가 조용히 죽으면 evidence 가 null 이 되는데,
# 예전에는 그래도 집계기가 0 으로 끝나 CI 가 초록이었다. 이제는 실패로 본다.
declare -a missing=()
run_report(){
  local name=$1 cmd=$2 tmp rc=0 last
  tmp=$(mktemp)
  if bash -c "$cmd" >"$tmp" 2>&1; then rc=0; else rc=$?; fi
  last=$(tail -n 1 "$tmp" || true)
  if python3 -c 'import json,sys; json.loads(sys.argv[1])' "$last" >/dev/null 2>&1; then
    reports+=("{\"name\":\"$name\",\"exit_code\":$rc,\"evidence\":$last}")
  else
    reports+=("{\"name\":\"$name\",\"exit_code\":$rc,\"evidence\":null}")
    missing+=("$name")
    printf '%s: 파싱 가능한 evidence 를 만들지 못했습니다 (exit=%s)\n' "$name" "$rc" >&2
    printf '  마지막 출력: %s\n' "${last:-<빈 출력>}" >&2
  fi
  rm -f "$tmp"
}
[ -f "$ROOT/tools/node-readiness-attest.sh" ] && run_report readiness "READINESS_OUTPUT=/tmp/readiness.json bash $ROOT/tools/node-readiness-attest.sh" || true
[ -f "$ROOT/network/node-network-readiness.sh" ] && run_report network "bash $ROOT/network/node-network-readiness.sh" || true
[ -f "$ROOT/storage/node-storage-readiness.sh" ] && run_report storage "bash $ROOT/storage/node-storage-readiness.sh" || true
[ -f "$ROOT/time/node-time-readiness.sh" ] && run_report time "bash $ROOT/time/node-time-readiness.sh" || true
[ -f "$ROOT/security/workload-security-check.sh" ] && run_report security "bash $ROOT/security/workload-security-check.sh" || true
[ -f "$ROOT/rocky/preflight.sh" ] && [ "${RUN_ROCKY_PROFILE:-0}" = 1 ] && run_report rocky "bash $ROOT/rocky/preflight.sh" || true
[ -f "$ROOT/nixos/preflight.sh" ] && [ "${RUN_NIXOS_PROFILE:-0}" = 1 ] && run_report nixos "bash $ROOT/nixos/preflight.sh" || true
[ -f "$ROOT/observability/node-diagnostic-profile.sh" ] && [ "${RUN_OBSERVABILITY_PROFILE:-0}" = 1 ] && run_report observability "DIAGNOSTIC_DURATION_SECONDS=${DIAGNOSTIC_DURATION_SECONDS:-1} bash $ROOT/observability/node-diagnostic-profile.sh" || true
[ -f "$ROOT/tools/sbom-license-gate.sh" ] && [ "${RUN_LICENSE_GATE:-0}" = 1 ] && run_report license "bash $ROOT/tools/sbom-license-gate.sh" || true
python3 - "$OUT" "$(IFS=,; echo "${reports[*]:-}")" "$(IFS=,; echo "${missing[*]:-}")" <<'PY'
import json,sys
out,raw,miss=sys.argv[1:]
reports=json.loads('['+raw+']') if raw else []
obj={'schema':'kube-ready-contracts/v1','reports':reports,
     'evidence_missing':[m for m in miss.split(',') if m],'offline':True}
open(out,'w').write(json.dumps(obj,sort_keys=True,separators=(',',':'))+'\n')
print(json.dumps(obj,sort_keys=True,separators=(',',':')))
PY

# evidence 없음은 환경 문제가 아니라 도구 결함이다. status=FAIL 은 정상적인 검사 결과이므로
# 여기서 막지 않는다. 예외가 필요할 때만 ALLOW_MISSING_EVIDENCE=1 로 통과시킨다.
if [ "${#missing[@]}" -gt 0 ] && [ "${ALLOW_MISSING_EVIDENCE:-0}" != 1 ]; then
  printf 'evidence 를 만들지 못한 리포트: %s\n' "${missing[*]}" >&2
  exit 1
fi
