#!/usr/bin/env bash
set -euo pipefail

# Local/Claude QA runner. Hypervisor tests are intentionally host-side.
# MATRIX format: provider|box[,provider|box,...]
# Example:
# MATRIX='vmware_desktop|test/ubuntu-24.04,virtualbox|test/ubuntu-24.04-vbox'

MATRIX="${MATRIX:-${PROVIDER:-vmware_desktop}|${BOX:-test/ubuntu-24.04}}"
STRICT_RUNTIME="${STRICT_RUNTIME:-1}"
RFP_PROFILE="${RFP_PROFILE:-1}"
OUTPUT="${OUTPUT:-matrix-evidence.json}"

command -v vagrant >/dev/null || { echo 'vagrant required' >&2; exit 2; }
command -v python3 >/dev/null || { echo 'python3 required' >&2; exit 2; }

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

  cleanup_case "$dir"
  if ! (cd "$dir" && VAGRANT_BOX="$box" vagrant up --provider="$provider"); then
    status=FAIL
  elif ! (cd "$dir" && STRICT_RUNTIME="$STRICT_RUNTIME" RFP_PROFILE="$RFP_PROFILE" bash ../verify_box.sh "$provider" --strict-runtime --rfp-profile --narwhal-output "$evidence"); then
    status=FAIL
  elif [ ! -s "$evidence" ] || ! python3 -m json.tool "$evidence" >/dev/null 2>&1; then
    status=FAIL
  fi

  [ "$status" = PASS ] || overall=1
  case_json=$(python3 - "$provider" "$box" "$status" "$evidence" <<'PY'
import json,sys
provider,box,status,path=sys.argv[1:]
obj={'provider':provider,'box':box,'status':status}
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
