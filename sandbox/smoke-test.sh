#!/usr/bin/env bash
set -euo pipefail

RUNTIME_CLASS="${RUNTIME_CLASS:-gvisor}"
NAMESPACE="${NAMESPACE:-kube-ready-sandbox-test}"

command -v kubectl >/dev/null || { echo 'kubectl required' >&2; exit 2; }
kubectl get runtimeclass "$RUNTIME_CLASS" >/dev/null 2>&1 || { echo "RuntimeClass $RUNTIME_CLASS unavailable" >&2; exit 3; }

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
trap 'kubectl delete namespace "$NAMESPACE" --ignore-not-found >/dev/null 2>&1 || true' EXIT

cat <<EOF | kubectl -n "$NAMESPACE" apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: sandbox-smoke
spec:
  runtimeClassName: $RUNTIME_CLASS
  automountServiceAccountToken: false
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: test
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
    resources:
      requests: {cpu: 10m, memory: 16Mi}
      limits: {cpu: 100m, memory: 64Mi}
    securityContext:
      allowPrivilegeEscalation: false
      capabilities: {drop: ["ALL"]}
EOF
kubectl -n "$NAMESPACE" wait --for=condition=Ready pod/sandbox-smoke --timeout=120s
kubectl -n "$NAMESPACE" get pod sandbox-smoke -o jsonpath='{.status.containerStatuses[0].containerID}'
echo
kubectl -n "$NAMESPACE" exec sandbox-smoke -- sh -c 'id; cat /proc/self/status | grep -E "NoNewPrivs|Seccomp"'
