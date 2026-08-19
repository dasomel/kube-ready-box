#!/usr/bin/env bash
set -euo pipefail

# Local/Claude QA runner. It never runs in GitHub-hosted CI because the required
# hypervisors are host capabilities. Build artifacts/box names are supplied by env.
PROVIDER="${PROVIDER:-vmware_desktop}"
BOX="${BOX:-test/ubuntu-24.04}"
STRICT_RUNTIME="${STRICT_RUNTIME:-1}"
RFP_PROFILE="${RFP_PROFILE:-1}"

case "$PROVIDER" in
  vmware_desktop) DIR="$(dirname "$0")/vmware";;
  virtualbox) DIR="$(dirname "$0")/virtualbox";;
  *) echo "unsupported provider: $PROVIDER" >&2; exit 2;;
esac

[ -f "$DIR/Vagrantfile" ] || { echo "missing $DIR/Vagrantfile" >&2; exit 2; }

export VAGRANT_DEFAULT_PROVIDER="$PROVIDER"
export VAGRANT_BOX="$BOX"

tmp=$(mktemp -d)
cleanup(){ (cd "$DIR" && vagrant destroy -f >/dev/null 2>&1 || true); rm -rf "$tmp"; }
trap cleanup EXIT

(cd "$DIR" && VAGRANT_BOX="$BOX" vagrant up --provider="$PROVIDER")
(cd "$DIR" && STRICT_RUNTIME="$STRICT_RUNTIME" RFP_PROFILE="$RFP_PROFILE" bash ../verify_box.sh "$PROVIDER" --strict-runtime --rfp-profile --narwhal-output "$tmp/readiness.json")

if [ -s "$tmp/readiness.json" ]; then
  python3 -m json.tool "$tmp/readiness.json" >/dev/null
  echo "Matrix smoke: PASS ($PROVIDER / $BOX)"
else
  echo "Matrix smoke: missing machine-readable report" >&2
  exit 1
fi
