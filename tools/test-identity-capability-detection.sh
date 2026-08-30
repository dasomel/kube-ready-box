#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Regression test for the Secure Boot / TPM capability detection block in
# packer/scripts/98-first-boot-identity.sh (issue #14). Real /sys/firmware/efi
# and /dev/tpm* can't be faked from a container or CI runner, so the detection
# block reads its paths from KUBE_READY_EFIVARS_DIR / KUBE_READY_TPM_DEVICES /
# KUBE_READY_TPM_VERSION_FILE (defaulted to the real paths in production).
# This test points those at fixtures and runs the *exact* committed block
# (extracted between the BEGIN/END markers, not retyped) so a regression like
# Mistake Pattern #20's bare `[ ] && var=` class of bug fails here first.
#
# Usage: tools/test-identity-capability-detection.sh
# Requires: docker (runs under Ubuntu-like coreutils, matching the real
# target -- macOS/BSD `od` flags differ from GNU `od`, see mistakes-log #23).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/packer/scripts/98-first-boot-identity.sh"
WORK="$REPO_ROOT/.test-identity-capability-detection"
rm -rf "$WORK"
mkdir -p "$WORK"

awk '/# --- BEGIN CAPABILITY DETECTION ---/{f=1} f; /# --- END CAPABILITY DETECTION ---/{exit}' "$SRC" \
  > "$WORK/detection-block.sh"
if [ ! -s "$WORK/detection-block.sh" ]; then
  echo "FAIL: could not extract capability-detection block from $SRC (markers missing/renamed?)" >&2
  exit 1
fi

cat > "$WORK/run-case.sh" <<'RUNNER'
#!/bin/bash
set -euo pipefail
source /w/detection-block.sh
echo "secure_boot_status=$secure_boot_status"
echo "secure_boot_detail=$secure_boot_detail"
echo "tpm_status=$tpm_status"
echo "tpm_detail=$tpm_detail"
RUNNER

fail=0
run_case() {
  local name="$1" expect_sb="$2" expect_tpm="$3"
  shift 3
  local out rc=0
  out=$(docker run --rm -e KUBE_READY_EFIVARS_DIR -e KUBE_READY_TPM_DEVICES -e KUBE_READY_TPM_VERSION_FILE \
    -v "$WORK:/w" -w /w "$@" ubuntu:24.04 bash /w/run-case.sh 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "FAIL [$name]: script exited $rc (should always exit 0, never abort under set -e)"
    echo "$out" | sed 's/^/    /'
    fail=1
    return
  fi
  local got_sb got_tpm
  got_sb=$(printf '%s\n' "$out" | grep '^secure_boot_status=' | cut -d= -f2)
  got_tpm=$(printf '%s\n' "$out" | grep '^tpm_status=' | cut -d= -f2)
  if [ "$got_sb" != "$expect_sb" ] || [ "$got_tpm" != "$expect_tpm" ]; then
    echo "FAIL [$name]: expected secure_boot=$expect_sb tpm=$expect_tpm, got secure_boot=$got_sb tpm=$got_tpm"
    echo "$out" | sed 's/^/    /'
    fail=1
    return
  fi
  echo "PASS [$name]: secure_boot=$got_sb tpm=$got_tpm"
}

# --- fixtures ---
mkdir -p "$WORK/no-efi/absent"
mkdir -p "$WORK/efi-no-var"
mkdir -p "$WORK/efi-var-enabled"
printf '\x07\x00\x00\x00\x01' > "$WORK/efi-var-enabled/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
mkdir -p "$WORK/efi-var-disabled"
printf '\x07\x00\x00\x00\x00' > "$WORK/efi-var-disabled/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
mkdir -p "$WORK/efi-var-unreadable/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
mkdir -p "$WORK/tpm-none"
mkdir -p "$WORK/tpm-with-version/dev" "$WORK/tpm-with-version/sys"
: > "$WORK/tpm-with-version/dev/tpm0"
printf '2\n' > "$WORK/tpm-with-version/sys/tpm_version_major"
mkdir -p "$WORK/tpm-no-version/dev"
: > "$WORK/tpm-no-version/dev/tpm0"

KUBE_READY_EFIVARS_DIR="/w/no-efi/absent-does-not-exist" \
KUBE_READY_TPM_DEVICES="/w/tpm-none/dev/tpm0" \
KUBE_READY_TPM_VERSION_FILE="/w/tpm-none/sys/tpm_version_major" \
  run_case "no-uefi + no-tpm" unavailable unavailable

KUBE_READY_EFIVARS_DIR="/w/efi-no-var" \
KUBE_READY_TPM_DEVICES="/w/tpm-none/dev/tpm0" \
KUBE_READY_TPM_VERSION_FILE="/w/tpm-none/sys/tpm_version_major" \
  run_case "uefi-present, var missing" unavailable unavailable

KUBE_READY_EFIVARS_DIR="/w/efi-var-enabled" \
KUBE_READY_TPM_DEVICES="/w/tpm-with-version/dev/tpm0" \
KUBE_READY_TPM_VERSION_FILE="/w/tpm-with-version/sys/tpm_version_major" \
  run_case "secure boot enabled + tpm supported" supported supported

KUBE_READY_EFIVARS_DIR="/w/efi-var-disabled" \
KUBE_READY_TPM_DEVICES="/w/tpm-no-version/dev/tpm0" \
KUBE_READY_TPM_VERSION_FILE="/w/tpm-no-version/does-not-exist" \
  run_case "secure boot disabled + tpm partial" partial partial

# Regression fixture for the Codex-reviewed P2 bug: -r reports the path
# readable (it's a directory), but `od` cannot read a directory as data, so
# the pipeline fails. Before the `|| true` fix this aborted the whole
# first-boot service under set -e instead of falling through to the
# "unreadable" branch.
KUBE_READY_EFIVARS_DIR="/w/efi-var-unreadable" \
KUBE_READY_TPM_DEVICES="/w/tpm-none/dev/tpm0" \
KUBE_READY_TPM_VERSION_FILE="/w/tpm-none/sys/tpm_version_major" \
  run_case "secure boot var read fails after -r check (regression)" unavailable unavailable

rm -rf "$WORK"
exit "$fail"
