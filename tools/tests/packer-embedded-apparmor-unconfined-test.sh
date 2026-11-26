#!/usr/bin/env bash
# Deterministic fixture coverage for mistakes-log #34: the
# `sysctl_kernel_apparmor_restrict_unprivileged_unconfined` check inside the
# `k8s-node-preflight` CLI that packer/scripts/09-k8s-node-preflight.sh embeds
# must FAIL when the Ubuntu restriction is on (runc container labels become
# `<profile>//&unconfined` and intra-container signals are denied), PASS at 0,
# and never report a present-but-unreadable knob as healthy.
#
# Same technique as tools/tests/packer-embedded-apparmor-test.sh: extract the
# literal heredoc body (the bytes installed to /usr/local/bin/k8s-node-preflight)
# and run it whole, with a PATH-shimmed `cat` answering only the literal /proc
# path. Other checks are expected to FAIL/UNKNOWN on a test host; only this
# check is asserted. Must pass on both macOS and Linux.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

KNOB=/proc/sys/kernel/apparmor_restrict_unprivileged_unconfined
CHECK=sysctl_kernel_apparmor_restrict_unprivileged_unconfined

script="$WORKDIR/09-embedded.sh"
sed -n "/^cat >.*<<'VALIDATOR'\$/,/^VALIDATOR\$/p" "$ROOT/packer/scripts/09-k8s-node-preflight.sh" | sed '1d;$d' > "$script"
[ -s "$script" ] || { echo "::error::09-k8s-node-preflight.sh heredoc extraction produced nothing" >&2; exit 1; }
chmod +x "$script"

real_cat=$(command -v cat)

# write_cat_shim <bindir> <mode> <value>; mode: present | absent
write_cat_shim() {
  local bindir=$1 mode=$2 value=$3
  mkdir -p "$bindir"
  cat > "$bindir/cat" <<SHIM
#!/usr/bin/env bash
set -euo pipefail
if [ "\$#" -eq 1 ] && [ "\$1" = "$KNOB" ]; then
  case "$mode" in
    present) printf '%s\n' "$value"; exit 0 ;;
    absent) echo "cat: $KNOB: No such file or directory" >&2; exit 1 ;;
  esac
fi
exec "$real_cat" "\$@"
SHIM
  chmod +x "$bindir/cat"
}

run_case() {
  local name=$1 mode=$2 value=$3
  local bindir="$WORKDIR/bin-$name" out="$WORKDIR/$name.json"
  write_cat_shim "$bindir" "$mode" "$value"
  set +e
  PATH="$bindir:$PATH" bash "$script" json >"$out" 2>"$WORKDIR/$name.stderr"
  set -e
  python3 -m json.tool "$out" >/dev/null || {
    echo "::error::$name did not produce parseable JSON" >&2
    cat "$WORKDIR/$name.stderr" >&2
    exit 1
  }
  echo "$out"
}

assert_check() {
  local out=$1 status=$2 detail=$3
  python3 - "$out" "$CHECK" "$status" "$detail" <<'PY'
import json, sys
path, name, expected_status, expected_detail = sys.argv[1:]
matches = [c for c in json.load(open(path, encoding="utf-8")).get("checks", []) if c.get("name") == name]
if len(matches) != 1:
    print(f"::error::{path}: expected exactly one check name={name!r}, found {len(matches)}")
    raise SystemExit(1)
got = (matches[0].get("status"), matches[0].get("detail"))
if got != (expected_status, expected_detail):
    print(f"::error::{path}: {name} expected {expected_status}/{expected_detail!r}, got {got[0]}/{got[1]!r}")
    raise SystemExit(1)
PY
}

# --- allow: restriction off -> PASS ---
assert_check "$(run_case unconfined-0 present 0)" PASS 0

# --- deny: Ubuntu 26.04 default -> FAIL ---
assert_check "$(run_case unconfined-1 present 1)" FAIL "expected=0 actual=1"

# --- deny: empty read -> never PASS ---
out=$(run_case unconfined-empty present "")
if [ -e "$KNOB" ]; then
  assert_check "$out" UNKNOWN "present but unreadable"
else
  assert_check "$out" PASS "not present on this kernel"
fi

# --- read fails: knob present on host -> UNKNOWN; absent (macOS, other kernels) -> PASS ---
out=$(run_case unconfined-absent absent "")
if [ -e "$KNOB" ]; then
  assert_check "$out" UNKNOWN "present but unreadable"
else
  assert_check "$out" PASS "not present on this kernel"
fi

echo "packer-embedded-apparmor-unconfined-test.sh: all scenarios passed"
