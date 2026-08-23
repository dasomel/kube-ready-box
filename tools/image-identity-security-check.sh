#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-/}"

if [ "${ALLOW_HOST_ROOT:-0}" != "1" ]; then
  RESOLVED="$(realpath -- "$ROOT" 2>/dev/null || readlink -f -- "$ROOT" 2>/dev/null || printf '%s' "$ROOT")"
  case "$RESOLVED" in
    /)
      echo "ERROR: refusing to audit '$ROOT' (resolves to /): this tool audits an EXTRACTED BOX IMAGE root, not the live host." >&2
      echo "Pass an explicit path to the extracted/mounted box image, or set ALLOW_HOST_ROOT=1 if intentionally running inside the guest during provisioning." >&2
      exit 1
      ;;
  esac
fi

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
