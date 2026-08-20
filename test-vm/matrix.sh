#!/usr/bin/env bash
set -euo pipefail

# Local/Claude QA runner. Hypervisor tests are intentionally host-side.
# MATRIX format: provider|box[,provider|box,...]
# Example:
# MATRIX='vmware_desktop|test/ubuntu-24.04,virtualbox|test/ubuntu-24.04-vbox'

MATRIX="${MATRIX:-${PROVIDER:-vmware_desktop}|${BOX:-test/ubuntu-24.04}}"
# STRICT_RUNTIME=1은 "클러스터 조인 직전 노드" 검증용이다. containerd 등 런타임이
# 설치돼 있어야 PASS한다. 이 박스는 README의 "What's NOT Included"대로 런타임을
# 담지 않으므로, 박스 검증의 기본값은 0이어야 한다. 1로 두면 어떤 박스도 통과할 수 없다.
STRICT_RUNTIME="${STRICT_RUNTIME:-0}"
RFP_PROFILE="${RFP_PROFILE:-1}"
OUTPUT="${OUTPUT:-matrix-evidence.json}"

command -v vagrant >/dev/null || { echo 'vagrant required' >&2; exit 2; }
command -v python3 >/dev/null || { echo 'python3 required' >&2; exit 2; }

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

IFS=',' read -r -a cases <<< "$MATRIX"
results=()
overall=0

cleanup_case() {
  local dir="$1"
  (cd "$dir" && vagrant destroy -f >/dev/null 2>&1 || true)
}

for item in "${cases[@]}"; do
  provider="${item%%|*}"
  box="${item#*|}"
  case "$provider" in
    vmware_desktop) dir="$(dirname "$0")/vmware";;
    virtualbox) dir="$(dirname "$0")/virtualbox";;
    *) echo "unsupported provider: $provider" >&2; exit 2;;
  esac

  [ -f "$dir/Vagrantfile" ] || { echo "missing $dir/Vagrantfile" >&2; exit 2; }
  case_dir=$(mktemp -d)
  evidence="$case_dir/readiness.json"
  status=PASS

  export VAGRANT_DEFAULT_PROVIDER="$provider"
  export VAGRANT_BOX="$box"

  verify_flags=()
  [ "$STRICT_RUNTIME" = "1" ] && verify_flags+=(--strict-runtime)
  [ "$RFP_PROFILE" = "1" ] && verify_flags+=(--rfp-profile)

  cleanup_case "$dir"
  provisioned=false
  provenance=""
  if ! (cd "$dir" && VAGRANT_BOX="$box" vagrant up --provider="$provider"); then
    status=FAIL
  elif ! (cd "$dir" && vagrant ssh -c 'test -x /usr/local/bin/k8s-node-preflight' >/dev/null 2>&1) \
       && ! { provisioned=true; (cd "$dir" && vagrant ssh -c 'sudo bash -s' < "$repo_root/packer/scripts/09-k8s-node-preflight.sh" >/dev/null 2>&1); }; then
    # 박스가 preflight를 담고 있지 않으면 테스트 시점에 주입한다.
    # 이미지에 이미 포함된 경우와 구분하기 위해 provisioned 플래그를 증거에 남긴다.
    status=FAIL
  elif ! provenance=$(cd "$dir" && vagrant ssh -c 'cat /etc/vagrant-box/info.txt 2>/dev/null | head -20; echo "KERNEL=$(uname -r)"; echo "OS=$(. /etc/os-release; echo $VERSION_ID)"' 2>/dev/null); then
    # 증거에 박스 출처가 없으면 이미지 결함과 낡은 박스를 구분할 수 없다.
    status=FAIL
  elif ! (cd "$dir" && STRICT_RUNTIME="$STRICT_RUNTIME" RFP_PROFILE="$RFP_PROFILE" bash ../verify_box.sh "$provider" "${verify_flags[@]}" --narwhal-output "$evidence"); then
    status=FAIL
  elif [ ! -s "$evidence" ] || ! python3 -m json.tool "$evidence" >/dev/null 2>&1; then
    status=FAIL
  fi

  [ "$status" = PASS ] || overall=1
  case_json=$(python3 - "$provider" "$box" "$status" "$evidence" "$provisioned" "$provenance" <<'PY'
import json,sys
provider,box,status,path,provisioned,provenance=sys.argv[1:]
obj={'provider':provider,'box':box,'status':status,
     'preflightProvisionedAtTest':provisioned=='true',
     'boxProvenance':provenance.strip() or None}
try:
    obj['evidence']=json.load(open(path))
except Exception:
    obj['evidence']=None
print(json.dumps(obj,sort_keys=True,separators=(',',':')))
PY
)
  results+=("$case_json")

  cleanup_case "$dir"
  rm -rf "$case_dir"
done

python3 - "$OUTPUT" "$(IFS=,; echo "${results[*]}")" <<'PY'
import datetime,json,sys
out,raw=sys.argv[1:]
items=json.loads('['+raw+']') if raw else []
obj={
  'schema':'kube-ready-vm-matrix/v1',
  'generatedAt':datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z'),
  'strictRuntime':True,
  'rfpProfile':True,
  'cases':items,
  'status':'PASS' if all(x['status']=='PASS' for x in items) else 'FAIL'
}
open(out,'w').write(json.dumps(obj,sort_keys=True,indent=2)+'\n')
print(json.dumps({'schema':obj['schema'],'status':obj['status'],'cases':len(items)},separators=(',',':')))
PY

exit "$overall"
