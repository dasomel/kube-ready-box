#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EVIDENCE_SCRIPT="$REPO_ROOT/packer/scripts/100-image-security-evidence.sh"
IDENTITY_TOOL="$REPO_ROOT/tools/image-identity-security-check.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

make_inputs() {
  local tools_dir="$1"
  mkdir -p "$tools_dir"
  cp "$IDENTITY_TOOL" "$tools_dir/image-identity-security-check.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "{\\\"schema_version\\\":1,\\\"status\\\":\\\"PASS\\\"}\\n" > "$OUTPUT"' > "$tools_dir/sbom-license-gate.sh"
  : > "$tools_dir/license-policy.conf"
  : > "$tools_dir/license-exceptions.tsv"
}

# A 0-byte machine-id is the expected image reset state and must pass.
pass_root="$tmpdir/pass-root"
pass_tools="$tmpdir/pass-tools"
pass_evidence="$tmpdir/pass-evidence"
mkdir -p "$pass_root/etc/ssh"
: > "$pass_root/etc/machine-id"
make_inputs "$pass_tools"
KUBE_READY_BUILD_TOOLS_DIR="$pass_tools" EVIDENCE_DIR="$pass_evidence" IMAGE_ROOT="$pass_root" \
  bash "$EVIDENCE_SCRIPT" > "$tmpdir/pass.stdout" 2> "$tmpdir/pass.stderr"
grep -Fq '"status":"PASS"' "$pass_evidence/identity-security-report.json"
if command -v dpkg-query >/dev/null 2>&1; then
  grep -Fq '"status":"PASS"' "$pass_evidence/license-report.json"
else
  grep -Fq '"detail":"no-dpkg"' "$pass_evidence/license-report.json"
fi

# A populated machine-id must abort and preserve the identity checker reason.
fail_root="$tmpdir/fail-root"
fail_tools="$tmpdir/fail-tools"
mkdir -p "$fail_root/etc/ssh"
printf 'not-an-image-reset\n' > "$fail_root/etc/machine-id"
make_inputs "$fail_tools"
if KUBE_READY_BUILD_TOOLS_DIR="$fail_tools" EVIDENCE_DIR="$tmpdir/fail-evidence" IMAGE_ROOT="$fail_root" \
  bash "$EVIDENCE_SCRIPT" > "$tmpdir/fail.stdout" 2> "$tmpdir/fail.stderr"; then
  echo 'expected populated machine-id fixture to fail' >&2
  exit 1
fi
grep -Fq "FAIL private/identity artifact present: $fail_root/etc/machine-id" "$tmpdir/fail.stderr"

# A checker that emits no report must be INVALID and abort rather than pass.
empty_tools="$tmpdir/empty-tools"
mkdir -p "$empty_tools"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$empty_tools/image-identity-security-check.sh"
: > "$empty_tools/sbom-license-gate.sh"
: > "$empty_tools/license-policy.conf"
: > "$empty_tools/license-exceptions.tsv"
if KUBE_READY_BUILD_TOOLS_DIR="$empty_tools" EVIDENCE_DIR="$tmpdir/empty-evidence" IMAGE_ROOT="$pass_root" \
  bash "$EVIDENCE_SCRIPT" > "$tmpdir/empty.stdout" 2> "$tmpdir/empty.stderr"; then
  echo 'expected empty report fixture to fail' >&2
  exit 1
fi
grep -Fq 'identity: invalid status' "$tmpdir/empty.stderr"

echo 'image security evidence fixtures: PASS'
