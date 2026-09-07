#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
set -euo pipefail

# These tools are uploaded by the Packer file provisioners immediately before
# this script. They run after 99-cleanup.sh, so evidence describes the final
# image rather than an intermediate build state.
TOOLS_DIR="${KUBE_READY_BUILD_TOOLS_DIR:-/tmp}"
EVIDENCE_DIR="${EVIDENCE_DIR:-/etc/vagrant-box}"
IMAGE_ROOT="${IMAGE_ROOT:-/}"

identity_tool="$TOOLS_DIR/image-identity-security-check.sh"
license_tool="$TOOLS_DIR/sbom-license-gate.sh"
policy_file="$TOOLS_DIR/license-policy.conf"
exceptions_file="$TOOLS_DIR/license-exceptions.tsv"

# Remove Packer's four temporary evidence inputs after this final provisioner;
# only the reports in EVIDENCE_DIR are intended to remain in the box image.
trap 'rm -f "$identity_tool" "$license_tool" "$policy_file" "$exceptions_file"' EXIT

for required in "$identity_tool" "$license_tool" "$policy_file" "$exceptions_file"; do
  if [ ! -f "$required" ]; then
    echo "FAIL: required build-time evidence input is missing: $required" >&2
    exit 1
  fi
done

install -d -m 0755 "$EVIDENCE_DIR"

# This provisioner currently audits Debian/Ubuntu package metadata. Do not run
# the dpkg-only gate on a future RPM image: leave explicit UNKNOWN evidence.
no_dpkg=0
if ! command -v dpkg-query >/dev/null 2>&1; then
  no_dpkg=1
  printf '%s\n' '{"detail":"no-dpkg","schema_version":1,"status":"UNKNOWN"}' > "$EVIDENCE_DIR/license-report.json"
fi

# A checker can deliberately return non-zero for FAIL. Capture that result so
# evidence remains in the image, then make the build decision from JSON status:
# only FAIL is a build blocker; UNKNOWN remains auditable but non-blocking.
run_check() {
  local name="$1"
  local report="$2"
  shift 2
  local exit_code=0 status stdout

  stdout="${report}.stdout"
  rm -f "$report" "$stdout"
  "$@" > "$stdout" || exit_code=$?
  if [ ! -s "$report" ]; then
    cp "$stdout" "$report"
  fi
  status="$(python3 - "$report" <<'PY'
import json
import sys

try:
    path = sys.argv[1]
    with open(path, encoding="utf-8") as fh:
        lines = [line for line in fh if line.strip()]
    evidence = json.loads(lines[-1])
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(evidence, fh, sort_keys=True, separators=(",", ":"))
        fh.write("\n")
    print(evidence.get("status", "INVALID"))
except (OSError, ValueError, IndexError):
    print("INVALID")
PY
  )"

  if [ "$status" != "PASS" ] && [ -s "$stdout" ]; then
    echo "${name}: checker output follows:" >&2
    cat "$stdout" >&2
  fi
  rm -f "$stdout"

  case "$status" in
    PASS)
      echo "${name}: PASS"
      ;;
    UNKNOWN)
      echo "${name}: UNKNOWN (recorded; not a build blocker)" >&2
      ;;
    FAIL)
      echo "${name}: FAIL" >&2
      return 1
      ;;
    *)
      echo "${name}: invalid status '$status' (checker exit $exit_code)" >&2
      return 1
      ;;
  esac
}

run_check identity "$EVIDENCE_DIR/identity-security-report.json" \
  env ALLOW_HOST_ROOT=1 bash "$identity_tool" "$IMAGE_ROOT"
if [ "$no_dpkg" -eq 0 ]; then
  run_check license "$EVIDENCE_DIR/license-report.json" \
    env ROOT="$IMAGE_ROOT" EVIDENCE_DIR="$EVIDENCE_DIR" \
    POLICY_FILE="$policy_file" EXCEPTIONS_FILE="$exceptions_file" \
    OUTPUT="$EVIDENCE_DIR/license-report.json" bash "$license_tool"
else
  echo "license: UNKNOWN (no-dpkg; recorded; not a build blocker)" >&2
fi

chmod 0644 "$EVIDENCE_DIR/identity-security-report.json" "$EVIDENCE_DIR/license-report.json"
echo "=== image security evidence complete ==="
