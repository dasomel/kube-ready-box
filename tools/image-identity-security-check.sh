#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-/}"
fail=0

for f in "$ROOT/etc/ssh/ssh_host_rsa_key" "$ROOT/etc/ssh/ssh_host_ed25519_key" "$ROOT/etc/machine-id" "$ROOT/var/lib/dbus/machine-id"; do
  if [ -e "$f" ]; then echo "FAIL private/identity artifact present: $f"; fail=1; fi
done

# Detect obvious private-key material without traversing runtime mounts.
while IFS= read -r -d '' f; do
  if grep -Iq . "$f" 2>/dev/null && grep -Eq 'BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY' "$f" 2>/dev/null; then
    echo "FAIL private key material: $f"; fail=1
  fi
done < <(find "$ROOT/etc" "$ROOT/home" -xdev -type f -print0 2>/dev/null)

if [ "$fail" -eq 0 ]; then echo '{"schema":"kube-ready-identity/v1","status":"PASS","private_key_material":false,"machine_identity_present":false}'; else echo '{"schema":"kube-ready-identity/v1","status":"FAIL"}'; fi
exit "$fail"
