#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

CHECK="$ROOT/tools/template-consistency-check.sh"
WORK="$TMPDIR_TEST/packer"
mkdir -p "$WORK"
cp "$ROOT"/packer/*.pkr.hcl "$WORK/"

# 1. The real, undrifted template set must pass.
TEMPLATE_DIR="$WORK" bash "$CHECK" >/dev/null

# 2. The #47 reproduction: a provisioner wired into only one of the four ubuntu
# templates. `packer validate` and shellcheck both pass on this; this check
# must not.
printf '\n# injected by test\n# scripts/42-drift-probe.sh\n' >> "$WORK/virtualbox-amd64.pkr.hcl"
if TEMPLATE_DIR="$WORK" bash "$CHECK" >/dev/null 2>"$TMPDIR_TEST/drift.log"; then
  echo "FAIL: single-template provisioner drift was not detected" >&2
  exit 1
fi
grep -q "virtualbox-amd64.pkr.hcl" "$TMPDIR_TEST/drift.log" || {
  echo "FAIL: drift report does not name the drifted template" >&2
  cat "$TMPDIR_TEST/drift.log" >&2
  exit 1
}
cp "$ROOT/packer/virtualbox-amd64.pkr.hcl" "$WORK/virtualbox-amd64.pkr.hcl"

# 3. Reordering without adding or removing anything is also drift: the
# provisioner sequence is the documented execution order, not a set.
python3 - "$WORK/vmware-amd64.pkr.hcl" <<'PY'
import re
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    text = handle.read()
matches = list(re.finditer(r'scripts/[a-zA-Z0-9._-]+\.sh', text))
first, second = matches[0], matches[1]
swapped = (
    text[: first.start()]
    + second.group(0)
    + text[first.end() : second.start()]
    + first.group(0)
    + text[second.end() :]
)
with open(path, "w", encoding="utf-8") as handle:
    handle.write(swapped)
PY
if TEMPLATE_DIR="$WORK" bash "$CHECK" >/dev/null 2>&1; then
  echo "FAIL: provisioner reordering was not detected" >&2
  exit 1
fi
cp "$ROOT/packer/vmware-amd64.pkr.hcl" "$WORK/vmware-amd64.pkr.hcl"

# 4. Rocky templates form their own family: they legitimately differ from the
# ubuntu set and must not be reported as drift against it.
TEMPLATE_DIR="$WORK" bash "$CHECK" >/dev/null

# 5. An empty template directory is a broken invocation, not a silent pass.
mkdir -p "$TMPDIR_TEST/empty"
if TEMPLATE_DIR="$TMPDIR_TEST/empty" bash "$CHECK" >/dev/null 2>&1; then
  echo "FAIL: empty template directory unexpectedly passed" >&2
  exit 1
fi

echo "template consistency check tests: PASS"
