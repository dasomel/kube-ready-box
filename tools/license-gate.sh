#!/usr/bin/env bash
set -euo pipefail

INVENTORY="${1:-/etc/vagrant-box/packages.txt}"
POLICY="${2:-etc/license-policy.txt}"
REPORT="${LICENSE_REPORT:-/etc/vagrant-box/license-report.json}"

[ -s "$INVENTORY" ] || { echo "missing package inventory: $INVENTORY" >&2; exit 2; }
[ -s "$POLICY" ] || { echo "missing license policy: $POLICY" >&2; exit 2; }

# The OS package inventory may not contain normalized SPDX license identifiers.
# This gate therefore fails only on explicitly classified forbidden identifiers
# supplied by a prior license scanner; it never guesses a license from package name.
forbidden=0
matches=()
while IFS= read -r policy; do
  case "$policy" in ''|'#'*) continue;; esac
  if grep -Fqi "$policy" "$INVENTORY"; then
    forbidden=$((forbidden+1)); matches+=("$policy")
  fi
done < "$POLICY"

python3 - "$REPORT" "$forbidden" "${matches[*]:-}" <<'PY'
import json,sys
out,n,m=sys.argv[1],int(sys.argv[2]),sys.argv[3]
obj={'schema':'kube-ready-license/v1','status':'FAIL' if n else 'PASS','forbidden_matches':([x for x in m.split() if x] if m else []),'policy_enforced':True,'license_unknowns':'not-inferred'}
open(out,'w').write(json.dumps(obj,sort_keys=True,separators=(',',':'))+'\n')
print(json.dumps(obj,sort_keys=True,separators=(',',':')))
PY
[ "$forbidden" -eq 0 ]
