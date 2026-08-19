#!/bin/bash
set -euo pipefail

TARGET_PROVIDER="${1:-}"
STRICT_RUNTIME="${STRICT_RUNTIME:-0}"

echo "=== Kubernetes node preflight verification: $(date) ==="
if [ -n "$TARGET_PROVIDER" ]; then
  echo "Provider: ${TARGET_PROVIDER}"
fi
echo "Strict runtime: ${STRICT_RUNTIME}"
echo ""

vagrant ssh -c "sudo STRICT_RUNTIME=${STRICT_RUNTIME} /usr/local/bin/k8s-node-preflight text"

echo ""
echo "=== Machine-readable report ==="
vagrant ssh -c "sudo STRICT_RUNTIME=${STRICT_RUNTIME} /usr/local/bin/k8s-node-preflight json"
