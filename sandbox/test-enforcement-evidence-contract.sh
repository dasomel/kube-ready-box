#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

cat >"$TMP/bin/kubectl" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
args="$*"
case "$args" in
  "create namespace "*" --dry-run=client -o yaml")
    printf '%s\n' 'apiVersion: v1' 'kind: Namespace' 'metadata:' '  name: test'
    ;;
  "apply -f -")
    cat >/dev/null
    ;;
  "get runtimeclass gvisor -o json")
    printf '%s\n' '{"apiVersion":"node.k8s.io/v1","kind":"RuntimeClass","metadata":{"name":"gvisor"},"handler":"runsc"}'
    ;;
  "-n kube-ready-sandbox-test apply -f -")
    cat >/dev/null
    ;;
  "-n kube-ready-sandbox-test wait --for=condition=Ready pod/sandbox-evidence --timeout=120s")
    ;;
  "-n kube-ready-sandbox-test get pod sandbox-evidence -o jsonpath={.status.containerStatuses[0].containerID}")
    printf '%s' 'containerd://fixture-container-id'
    ;;
  "-n kube-ready-sandbox-test exec sandbox-evidence -- sh -c "*)
    printf '%s\n' 'NoNewPrivs: 1' 'Seccomp: 2' 'PID1=/pause'
    ;;
  "get runtimeclass kube-ready-negative-do-not-exist")
    exit 1
    ;;
  "-n kube-ready-sandbox-test apply --dry-run=server -f -")
    cat >/dev/null
    printf '%s\n' 'RuntimeClass "kube-ready-negative-do-not-exist" not found' >&2
    exit 1
    ;;
  "delete namespace kube-ready-sandbox-test --ignore-not-found")
    ;;
  *)
    printf 'unexpected fake kubectl invocation: %s\n' "$args" >&2
    exit 97
    ;;
esac
FAKE
chmod +x "$TMP/bin/kubectl"

OUTPUT="$TMP/evidence.json"
RESOLUTION_ID='resolution:test:123' \
INVOCATION_DIGEST='sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
PATH="$TMP/bin:$PATH" \
OUTPUT="$OUTPUT" \
bash "$ROOT/sandbox/verify-sandbox-evidence.sh" >/dev/null

python3 - "$OUTPUT" <<'PY'
import hashlib,json,sys
p=sys.argv[1]
data=json.load(open(p))
assert data['schema']=='kube-ready-sandbox/v1'
assert data['role']=='enforcement-evidence-provider'
assert data['status']=='PASS'
assert data['lifecycle']=={
  'declared':'PASS','supported':'PASS','effective':'PASS','verified':'PASS'
}
assert data['checks']['missingRuntimeClassRejected']=='PASS'
assert data['negativeProbe']['proves']=='runtime-enforcement-boundary'
assert data['negativeProbe']['doesNotProve']=='request-side-authorization'
assert data['correlation']['resolutionId']=='resolution:test:123'
assert data['correlation']['invocationDigest']=='sha256:'+'a'*64
assert data['correlation']['authoritySemantics']=='none-correlation-only'
digest=data.pop('evidenceDigest')
canonical=json.dumps(data,sort_keys=True,separators=(',',':'))
assert digest=='sha256:'+hashlib.sha256(canonical.encode()).hexdigest()
PY

if RESOLUTION_ID='resolution:test:bad' INVOCATION_DIGEST='not-a-digest' PATH="$TMP/bin:$PATH" OUTPUT="$TMP/bad.json" \
  bash "$ROOT/sandbox/verify-sandbox-evidence.sh" >/dev/null 2>&1; then
  echo 'invalid invocation digest was accepted' >&2
  exit 1
fi

echo 'sandbox enforcement evidence contract: PASS'
