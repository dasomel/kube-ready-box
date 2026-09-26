#!/usr/bin/env bash
# Deterministic fixture coverage for #44 T-020: the `apparmor` check inside
# the `k8s-node-preflight` CLI that packer/scripts/07-check-tuning.sh and
# packer/scripts/09-k8s-node-preflight.sh each embed (as a `cat
# <<'MARKER' ... MARKER` heredoc) must not PASS/UNKNOWN a disabled AppArmor
# on a capable kernel -- it reads the kernel module parameter (Y/N) and a
# confirmed-disabled module is FAIL.
#
# Extracts each heredoc's literal body into a standalone script (the exact
# bytes that get installed to /usr/local/bin/k8s-node-preflight at
# provisioning time -- this is "run the generated file", not a
# reimplementation) and runs it whole, with a PATH-shimmed `cat` answering
# only the literal `/sys/module/apparmor/parameters/enabled` read (D7: no
# production env-var bypass for the /sys path), the same technique as
# tools/tests/workload-lsm-stack-test.sh. The embedded script's other
# checks (kernel modules, containerd, packages, ...) are expected to be
# FAIL/UNKNOWN on a non-Ubuntu test host; only the `apparmor`/`Name: apparmor`
# entry is asserted. Must pass on both macOS and Linux.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# extract_heredoc <outer_script> <heredoc_terminator> <out_file>
# Strips the opening `cat > ... <<'TERMINATOR'` line and the closing bare
# TERMINATOR line, leaving exactly the heredoc body as a standalone script.
extract_heredoc() {
  local outer=$1 terminator=$2 out=$3
  sed -n "/^cat >.*<<'${terminator}'\$/,/^${terminator}\$/p" "$outer" | sed '1d;$d' > "$out"
  chmod +x "$out"
}

extract_heredoc "$ROOT/packer/scripts/07-check-tuning.sh" PREFLIGHT "$WORKDIR/07-embedded.sh"
extract_heredoc "$ROOT/packer/scripts/09-k8s-node-preflight.sh" VALIDATOR "$WORKDIR/09-embedded.sh"
[ -s "$WORKDIR/07-embedded.sh" ] || { echo "::error::07-check-tuning.sh heredoc extraction produced nothing" >&2; exit 1; }
[ -s "$WORKDIR/09-embedded.sh" ] || { echo "::error::09-k8s-node-preflight.sh heredoc extraction produced nothing" >&2; exit 1; }

real_cat=$(command -v cat)

# write_cat_shim <bindir> <mode> <value>
# mode: present (cat prints value) or absent (No such file or directory).
# Any other `cat` invocation (including the embedded script's own
# `cat "$report_file"`) passes through to the real binary unchanged.
write_cat_shim() {
  local bindir=$1 mode=$2 value=$3
  mkdir -p "$bindir"
  cat > "$bindir/cat" <<SHIM
#!/usr/bin/env bash
set -euo pipefail
if [ "\$#" -eq 1 ] && [ "\$1" = "/sys/module/apparmor/parameters/enabled" ]; then
  case "$mode" in
    present)
      printf '%s\n' "$value"
      exit 0
      ;;
    absent)
      echo "cat: /sys/module/apparmor/parameters/enabled: No such file or directory" >&2
      exit 1
      ;;
  esac
fi
exec "$real_cat" "\$@"
SHIM
  chmod +x "$bindir/cat"
}

run_case() {
  local script=$1 name=$2 mode=$3 value=$4
  local bindir="$WORKDIR/bin-$name"
  write_cat_shim "$bindir" "$mode" "$value"
  local out="$WORKDIR/$name.json"
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

# assert_07 <output.json> <status> <detail> -- 07's check id/status/detail schema.
assert_07() {
  local out=$1 status=$2 detail=$3
  python3 - "$out" "$status" "$detail" <<'PY'
import json, sys
path, expected_status, expected_detail = sys.argv[1:]
checks = json.load(open(path, encoding="utf-8")).get("checks", [])
matches = [c for c in checks if c.get("id") == "apparmor"]
if len(matches) != 1:
    print(f"::error::{path}: expected exactly one check id='apparmor', found {len(matches)}")
    raise SystemExit(1)
actual_status, actual_detail = matches[0].get("status"), matches[0].get("detail")
if actual_status != expected_status or actual_detail != expected_detail:
    print(f"::error::{path}: apparmor expected {expected_status}/{expected_detail!r}, "
          f"got {actual_status}/{actual_detail!r}")
    raise SystemExit(1)
PY
}

# assert_09 <output.json> <status> <detail> -- 09's check name/status/detail schema.
assert_09() {
  local out=$1 status=$2 detail=$3
  python3 - "$out" "$status" "$detail" <<'PY'
import json, sys
path, expected_status, expected_detail = sys.argv[1:]
checks = json.load(open(path, encoding="utf-8")).get("checks", [])
matches = [c for c in checks if c.get("name") == "apparmor"]
if len(matches) != 1:
    print(f"::error::{path}: expected exactly one check name='apparmor', found {len(matches)}")
    raise SystemExit(1)
actual_status, actual_detail = matches[0].get("status"), matches[0].get("detail")
if actual_status != expected_status or actual_detail != expected_detail:
    print(f"::error::{path}: apparmor expected {expected_status}/{expected_detail!r}, "
          f"got {actual_status}/{actual_detail!r}")
    raise SystemExit(1)
PY
}

for embedded in 07 09; do
  script="$WORKDIR/${embedded}-embedded.sh"
  assert_fn="assert_${embedded}"

  # --- allow: enabled (Y) -> PASS ---
  out=$(run_case "$script" "${embedded}-apparmor-enabled" present Y)
  "$assert_fn" "$out" PASS enabled

  # --- deny: disabled (N) -> FAIL, not aa-status-UNKNOWN ---
  out=$(run_case "$script" "${embedded}-apparmor-disabled" present N)
  "$assert_fn" "$out" FAIL disabled

  # --- deny: unexpected parameter value -> UNKNOWN, never PASS/FAIL ---
  out=$(run_case "$script" "${embedded}-apparmor-unexpected" present "?")
  "$assert_fn" "$out" UNKNOWN "unexpected value: ?"

  # --- deny: parameter unreadable -> UNKNOWN, never a PASS/FAIL guess ---
  out=$(run_case "$script" "${embedded}-apparmor-unreadable" absent "")
  "$assert_fn" "$out" UNKNOWN "AppArmor parameters unreadable"
done

echo "packer-embedded-apparmor-test.sh: all scenarios passed"
