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
cloud_state='SKIP unavailable'
installer_credentials='PASS absent'
cloud_disabled='absent'

for f in "$ROOT/etc/ssh/ssh_host_rsa_key" "$ROOT/etc/ssh/ssh_host_ed25519_key"; do
  if [ -e "$f" ]; then echo "FAIL private/identity artifact present: $f"; fail=1; fi
done

# D1: Keep residual instance data as WARN because shipped installers leave it
# behind; the cost is an informational finding, and the escape hatch is a
# separate provisioning change that removes it before this audit can FAIL it.
instances="$ROOT/var/lib/cloud/instances"
if [ -d "$instances" ]; then
  if find "$instances" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
    cloud_state='WARN instance-state-present'
    echo "WARN cloud-init instance state present: $instances"
  else
    cloud_state='PASS absent'
  fi
else
  cloud_state='PASS absent'
fi

# Installer user-data may contain password hashes or authorized keys. Report
# presence only; never print the matching line or its value.
installer_dir="$ROOT/etc/cloud/cloud.cfg.d"
if [ -d "$installer_dir" ]; then
  installer_credentials='PASS absent'
  while IFS= read -r -d '' f; do
    if grep -Eiq '^[[:space:]]*(passwd|hashed_passwd|password|ssh_authorized_keys)[[:space:]]*:' "$f" 2>/dev/null; then
      installer_credentials='WARN credential-material-present'
      echo "WARN installer cloud-init credential material present: $f"
    fi
  done < <(find "$installer_dir" -type f -iname '*installer*' -print0 2>/dev/null)
else
  installer_credentials='SKIP cloud-init-absent'
fi

if [ -d "$ROOT/etc/cloud" ]; then
  if [ -e "$ROOT/etc/cloud/cloud-init.disabled" ]; then cloud_disabled='disabled'; else cloud_disabled='enabled'; fi
fi

# An empty /etc/machine-id is the expected first-boot reset state. The dbus
# compatibility path must likewise be absent or empty; a populated ID leaks.
for f in "$ROOT/etc/machine-id" "$ROOT/var/lib/dbus/machine-id"; do
  if [ -s "$f" ]; then echo "FAIL private/identity artifact present: $f"; fail=1; fi
done

# Detect obvious private-key material without traversing runtime mounts.
while IFS= read -r -d '' f; do
  if grep -Iq . "$f" 2>/dev/null && grep -Eq 'BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY' "$f" 2>/dev/null; then
    echo "FAIL private key material: $f"; fail=1
  fi
done < <(find "$ROOT/etc" "$ROOT/home" -xdev -type f -print0 2>/dev/null)

if [ "$fail" -eq 0 ]; then echo "{\"schema\":\"kube-ready-identity/v1\",\"status\":\"PASS\",\"private_key_material\":false,\"machine_identity_present\":false,\"cloud_init_instance_state\":\"$cloud_state\",\"installer_credentials\":\"$installer_credentials\",\"cloud_init_disabled\":\"$cloud_disabled\"}"; else echo "{\"schema\":\"kube-ready-identity/v1\",\"status\":\"FAIL\",\"cloud_init_instance_state\":\"$cloud_state\",\"installer_credentials\":\"$installer_credentials\",\"cloud_init_disabled\":\"$cloud_disabled\"}"; fi
exit "$fail"
