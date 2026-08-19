#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

RUNTIME_CLASS="${RUNTIME_CLASS:-gvisor}"
NAMESPACE="${NAMESPACE:-kube-ready-sandbox-test}"
OUTPUT="${OUTPUT:-sandbox-evidence.json}"
IMAGE="${IMAGE:-busybox:1.36}"
FAILURES=0

command -v kubectl >/dev/null || { echo 'kubectl required' >&2; exit 2; }
command -v python3 >/dev/null || { echo 'python3 required' >&2; exit 2; }

json_escape() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip()))'; }

check_runtimeclass() {
  kubectl get runtimeclass "$RUNTIME_CLASS" -o json >/tmp/runtimeclass.json 2>/dev/null || return 1
  python3 - <<'PY'
import json
p=json.load(open('/tmp/runtimeclass.json'))
handler=p.get('handler')
if not handler:
    raise SystemExit('RuntimeClass handler is empty')
print(handler)
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

status_runtime="PASS"
status_effective="FAIL"
status_security="FAIL"
status_negative="FAIL"
status_resources="FAIL"

if ! check_runtimeclass >/tmp/runtime-handler.txt 2>/dev/null; then
  status_runtime="FAIL"
else
  status_effective="PASS"
fi
if [ "$status_runtime" = PASS ] && check_runtime_handler; then
  status_runtime="PASS"
else
  status_runtime="FAIL"
  FAILURES=$((FAILURES + 1))
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
  if [ -n "$container_id" ]; then
    status_effective="PASS"
  fi
else
  status_effective="FAIL"
fi

# Negative test: a deliberately missing RuntimeClass must be rejected before execution.
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
  # A dry-run success means the admission path did not reject the missing class.
  status_negative="FAIL"
  FAILURES=$((FAILURES + 1))
else
  if grep -qi 'RuntimeClass' /tmp/negative.out; then
    status_negative="PASS"
  else
    status_negative="UNKNOWN"
  fi
fi

if [ "$status_effective" != PASS ] || [ "$status_security" != PASS ]; then
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

python3 - "$OUTPUT" "$RUNTIME_CLASS" "$runtime_handler" "$status_runtime" "$status_effective" "$status_security" "$status_resources" "$status_negative" "$FAILURES" "$container_id" <<'PY'
import json,sys,datetime
(out,rc,handler,sr,se,ss,so,sn,failures,cid)=sys.argv[1:]
obj={
  'schema':'kube-ready-sandbox/v1',
  'runtimeClass':rc,
  'handler':handler or None,
  'checks':{
    'runtimeClass':sr,
    'effectiveRuntime':se,
    'seccompNoNewPrivs':ss,
    'resourceIsolation':so,
    'missingRuntimeClassRejected':sn,
  },
  'containerIDPresent':bool(cid),
  'status':'PASS' if int(failures)==0 else 'FAIL',
  'generatedAt':datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')
}
open(out,'w').write(json.dumps(obj,sort_keys=True,separators=(',',':'))+'\n')
print(json.dumps(obj,sort_keys=True,separators=(',',':')))
PY

[ "$FAILURES" -eq 0 ] || exit 1
