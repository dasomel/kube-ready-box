#!/usr/bin/env bash
# Deterministic fixture coverage for #44 T-015 (REQ-007, AC-006): the static
# host-mutation guard must pass the real tree, must fail per line/form (not
# per file) on an injected mutation naming file:line, must never flag a
# read-only invocation of the same tools, and an allowlisted file must still
# fail on a mutating form outside its specifically-approved lines.
#
# GUARD_ROOT points the guard at a plain (non-git) fixture directory -- the
# guard falls back to a directory walk when `git ls-files` finds nothing,
# specifically so this test does not need to `git init` a throwaway tree.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD="$ROOT/tools/host-mutation-guard.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# 1. The real, current tree must pass as-is (AC-006 allow).
bash "$GUARD" >/dev/null

# --- fixture tree for the injected-violation scenarios ---
FIXTURE="$WORKDIR/fixture"
mkdir -p "$FIXTURE/packer/scripts"
cp "$ROOT/packer/scripts/rocky-tuning.sh" "$FIXTURE/packer/scripts/rocky-tuning.sh"

run_guard() {
  set +e
  GUARD_ROOT="$FIXTURE" bash "$GUARD" >"$WORKDIR/out.log" 2>&1
  rc=$?
  set -e
  return "$rc"
}

# 2. The untouched fixture (just a copy of an already-allowlisted file) must
# still pass -- proves the allowlist itself, not just an empty tree, is fine.
if ! run_guard; then
  echo "FAIL: unmodified fixture tree did not pass" >&2
  cat "$WORKDIR/out.log" >&2
  exit 1
fi

# 3. Deny: `ufw enable` injected into a brand-new, non-allowlisted file must
# fail and name that file:line.
cat > "$FIXTURE/some-other-script.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ufw enable
EOF
if run_guard; then
  echo "FAIL: injected 'ufw enable' in a non-allowlisted file was not detected" >&2
  exit 1
fi
grep -q "some-other-script.sh:3:.*ufw" "$WORKDIR/out.log" || {
  echo "FAIL: violation report does not name some-other-script.sh:3" >&2
  cat "$WORKDIR/out.log" >&2
  exit 1
}
rm -f "$FIXTURE/some-other-script.sh"

# 4. Deny: `setenforce 0` added to an already-allowlisted file, outside its
# documented `setenforce 1` enforcing-preservation line, must still fail --
# the allowlist is per line/form, not per file.
printf 'setenforce 0\n' >> "$FIXTURE/packer/scripts/rocky-tuning.sh"
if run_guard; then
  echo "FAIL: 'setenforce 0' added to an allowlisted file was not detected" >&2
  exit 1
fi
grep -q "packer/scripts/rocky-tuning.sh:.*setenforce" "$WORKDIR/out.log" || {
  echo "FAIL: violation report does not name rocky-tuning.sh's injected line" >&2
  cat "$WORKDIR/out.log" >&2
  exit 1
}
# restore the allowlisted file to its original, passing form
cp "$ROOT/packer/scripts/rocky-tuning.sh" "$FIXTURE/packer/scripts/rocky-tuning.sh"
if ! run_guard; then
  echo "FAIL: fixture did not pass again after removing the injected line" >&2
  cat "$WORKDIR/out.log" >&2
  exit 1
fi

# 5. Allow: read-only invocations of every covered tool must pass anywhere,
# allowlisted or not -- kube-ready-box's own validators rely on this.
cat > "$FIXTURE/readonly-check.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
command -v nft >/dev/null 2>&1 && nft list ruleset
command -v ufw >/dev/null 2>&1 && ufw status
command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state
command -v getenforce >/dev/null 2>&1 && getenforce
command -v aa-status >/dev/null 2>&1 && aa-status
command -v iptables >/dev/null 2>&1 && iptables -S KUBE_READY_EGRESS
command -v iptables >/dev/null 2>&1 && iptables -L
EOF
if ! run_guard; then
  echo "FAIL: read-only firewall/LSM invocations were flagged" >&2
  cat "$WORKDIR/out.log" >&2
  exit 1
fi
rm -f "$FIXTURE/readonly-check.sh"

echo "host-mutation-guard-test.sh: all scenarios passed"
