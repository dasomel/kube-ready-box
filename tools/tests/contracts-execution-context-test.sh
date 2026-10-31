#!/usr/bin/env bash
# #54: kube-ready-contracts/v1 의 execution_context(커널/가상화/선언된 target)가
# 항상 존재하고, smolvm 선언 시 full_image_conformance 가 false, 아니면 UNKNOWN
# (절대 true 가 아님)인지 확인한다. 집계기 전체를 실제로 실행한다.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

run() { # run <outfile> [env...]
  local out=$1; shift
  # 개별 리포트의 FAIL/UNKNOWN 은 이 테스트의 관심사가 아니므로 종료코드는 무시한다.
  env -u KUBE_READY_EXECUTION_TARGET CONTRACT_OUTPUT="$out" "$@" \
    bash "$ROOT/tools/kube-ready-contracts.sh" >/dev/null 2>&1 || true
}

assert() { # assert <file> <python expr over d> <label>
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert eval(sys.argv[2]), d.get("execution_context")' "$1" "$2" \
    || { echo "FAIL: $3" >&2; exit 1; }
}

run "$WORKDIR/default.json"
assert "$WORKDIR/default.json" "d['schema']=='kube-ready-contracts/v1'" "schema kept"
assert "$WORKDIR/default.json" "set(d['execution_context'])=={'kernel_release','virtualization','declared_target','full_image_conformance'}" "execution_context keys"
assert "$WORKDIR/default.json" "d['execution_context']['kernel_release'] not in ('',None)" "kernel_release present"
assert "$WORKDIR/default.json" "d['execution_context']['declared_target']=='UNKNOWN'" "default declared_target UNKNOWN"
assert "$WORKDIR/default.json" "d['execution_context']['full_image_conformance']=='UNKNOWN'" "default conformance UNKNOWN"

run "$WORKDIR/smolvm.json" KUBE_READY_EXECUTION_TARGET=smolvm
assert "$WORKDIR/smolvm.json" "d['execution_context']['declared_target']=='smolvm'" "declared_target smolvm"
assert "$WORKDIR/smolvm.json" "d['execution_context']['full_image_conformance'] is False" "smolvm conformance false"

run "$WORKDIR/vbox.json" KUBE_READY_EXECUTION_TARGET=virtualbox
assert "$WORKDIR/vbox.json" "d['execution_context']['full_image_conformance']=='UNKNOWN'" "other target stays UNKNOWN, never true"

echo "contracts-execution-context: all scenarios passed"
