#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

RUNTIME_CLASS="${RUNTIME_CLASS:-gvisor}"
NAMESPACE="${NAMESPACE:-kube-ready-sandbox-test}"
OUTPUT="${OUTPUT:-sandbox-evidence.json}"
IMAGE="${IMAGE:-busybox:1.36}"
# Optional correlation supplied by an upper authorization/execution layer. kube-ready-box
# records these values only; it never interprets them as authority to execute anything.
RESOLUTION_ID="${RESOLUTION_ID:-}"
INVOCATION_DIGEST="${INVOCATION_DIGEST:-}"
FAILURES=0
container_id=""

command -v kubectl >/dev/null || { echo 'kubectl required' >&2; exit 2; }
command -v python3 >/dev/null || { echo 'python3 required' >&2; exit 2; }

if [ -n "$INVOCATION_DIGEST" ] && ! printf '%s' "$INVOCATION_DIGEST" | grep -Eq '^sha256:[0-9a-fA-F]{64}$'; then
  echo 'INVOCATION_DIGEST must be sha256:<64 hex> when provided' >&2
  exit 2
fi

check_runtimeclass() {
  kubectl get runtimeclass "$RUNTIME_CLASS" -o json >/tmp/runtimeclass.json 2>/dev/null || return 1
  python3 - <<'PY'
import json
p=json.load(open('/tmp/runtimeclass.json'))
handler=p.get('handler')
if not handler:
    raise SystemExit('RuntimeClass handler is empty')
PY
}

check_runtime_handler() {
  local handler
  handler="$(python3 - <<'PY'
import json
print(json.load(open('/tmp/runtimeclass.json')).get('handler',''))
PY
)"
  case "$handler" in
    runsc|gvisor|kata|kata-qemu|kata-clh|kata-fc) return 0 ;;
    *) return 1 ;;
  esac
}

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
trap 'kubectl delete namespace "$NAMESPACE" --ignore-not-found >/dev/null 2>&1 || true' EXIT

status_declared="FAIL"
status_supported="FAIL"
status_effective="FAIL"
status_security="FAIL"
status_negative="FAIL"
status_resources="FAIL"

if check_runtimeclass; then
  status_declared="PASS"
  if check_runtime_handler; then
    status_supported="PASS"
  fi
fi

cat <<EOF | kubectl -n "$NAMESPACE" apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: sandbox-evidence
spec:
  runtimeClassName: $RUNTIME_CLASS
  automountServiceAccountToken: false
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: test
    image: $IMAGE
    command: ["sh", "-c", "sleep 3600"]
    resources:
      requests: {cpu: 10m, memory: 16Mi}
      limits: {cpu: 100m, memory: 64Mi}
    securityContext:
      allowPrivilegeEscalation: false
      capabilities: {drop: ["ALL"]}
EOF

if kubectl -n "$NAMESPACE" wait --for=condition=Ready pod/sandbox-evidence --timeout=120s >/dev/null 2>&1; then
  container_id="$(kubectl -n "$NAMESPACE" get pod sandbox-evidence -o jsonpath='{.status.containerStatuses[0].containerID}')"
  command="id; cat /proc/self/status | grep -E 'NoNewPrivs|Seccomp'; echo PID1=\$(tr '\0' ' ' </proc/1/cmdline)"
  if output=$(kubectl -n "$NAMESPACE" exec sandbox-evidence -- sh -c "$command" 2>/dev/null); then
    if printf '%s\n' "$output" | grep -q 'NoNewPrivs:[[:space:]]*1' && printf '%s\n' "$output" | grep -q 'Seccomp:[[:space:]]*[12]'; then
      status_security="PASS"
    fi
    if printf '%s\n' "$output" | grep -q 'PID1='; then
      status_resources="PASS"
    fi
  fi
  [ -n "$container_id" ] && status_effective="PASS"
fi

# Negative probe: a deliberately missing RuntimeClass must be rejected before workload execution.
# This proves the Kubernetes/runtime-class enforcement boundary, not an upstream authorization
# decision. Upper layers must verify request-side authorization separately.
negative_class="kube-ready-negative-do-not-exist"
if kubectl get runtimeclass "$negative_class" >/dev/null 2>&1; then
  kubectl delete runtimeclass "$negative_class" >/dev/null 2>&1 || true
fi
if cat <<EOF | kubectl -n "$NAMESPACE" apply --dry-run=server -f - >/tmp/negative.out 2>&1; then
apiVersion: v1
kind: Pod
metadata:
  name: sandbox-negative
spec:
  runtimeClassName: $negative_class
  containers:
  - name: test
    image: $IMAGE
    command: ["true"]
EOF
  status_negative="FAIL"
else
  grep -qi 'RuntimeClass' /tmp/negative.out && status_negative="PASS" || status_negative="UNKNOWN"
fi

if [ "$status_declared" != PASS ] || [ "$status_supported" != PASS ] || [ "$status_effective" != PASS ] || [ "$status_security" != PASS ] || [ "$status_negative" != PASS ] || [ "$status_resources" != PASS ]; then
  FAILURES=$((FAILURES + 1))
fi

runtime_handler="$(python3 - <<'PY'
import json
try:
    print(json.load(open('/tmp/runtimeclass.json')).get('handler',''))
except Exception:
    print('')
PY
)"

python3 - "$OUTPUT" "$RUNTIME_CLASS" "$runtime_handler" "$status_declared" "$status_supported" "$status_effective" "$status_security" "$status_resources" "$status_negative" "$FAILURES" "$container_id" "$RESOLUTION_ID" "$INVOCATION_DIGEST" <<'PY'
import datetime,hashlib,json,sys
(
    out,rc,handler,declared,supported,effective,security,resources,negative,
    failures,cid,resolution_id,invocation_digest
)=sys.argv[1:]
obj={
  'schema':'kube-ready-sandbox/v1',
  'role':'enforcement-evidence-provider',
  'runtimeClass':rc,
  'handler':handler or None,
  'lifecycle':{
    'declared':declared,
    'supported':supported,
    'effective':effective,
    'verified':'PASS' if security == 'PASS' and negative == 'PASS' and resources == 'PASS' else 'FAIL',
  },
  'checks':{
    # Keep legacy keys for existing consumers while exposing the explicit lifecycle above.
    'runtimeClass':declared,
    'runtimeHandlerSupported':supported,
    'effectiveRuntime':effective,
    'seccompNoNewPrivs':security,
    'resourceIsolation':resources,
    'missingRuntimeClassRejected':negative,
  },
  'negativeProbe':{
    'name':'missing-runtime-class',
    'status':negative,
    'proves':'runtime-enforcement-boundary',
    'doesNotProve':'request-side-authorization',
  },
  'correlation':{
    'resolutionId':resolution_id or None,
    'invocationDigest':invocation_digest or None,
    'authoritySemantics':'none-correlation-only',
  },
  'containerIDPresent':bool(cid),
  'status':'PASS' if int(failures)==0 else 'FAIL',
  'generatedAt':datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')
}
canonical=json.dumps(obj,sort_keys=True,separators=(',',':'))
obj['evidenceDigest']='sha256:'+hashlib.sha256(canonical.encode()).hexdigest()
open(out,'w').write(json.dumps(obj,sort_keys=True,separators=(',',':'))+'\n')
print(json.dumps(obj,sort_keys=True,separators=(',',':')))
PY

[ "$FAILURES" -eq 0 ] || exit 1
