#!/usr/bin/env bash
# Deterministic fixture coverage for #44 T-010/T-011 (AC-001, AC-002):
# firewall_provider/firewall_state/firewall_rules must name the right manager
# and never collapse distinct UNKNOWN causes (tool-absent vs permission-denied
# vs status-unavailable vs empty-ruleset) into one bucket, and firewall_backend
# must keep its pre-#44 values. Runs the real network script with PATH built
# from a symlink farm of only the real utilities it needs plus per-scenario
# mock nft/ufw/firewall-cmd, so any real /usr/sbin/nft etc. on the test host
# never leaks in. Must pass on both macOS and Linux.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/network/node-network-readiness.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# Symlink farm of the real, unconditionally-needed utilities (grep/cut/tr/cat/
# basename/uname/mktemp/head/rm/python3). Deliberately excludes nft/ufw/
# firewall-cmd/iptables so scenarios control their presence exactly.
# grep is also relied on directly by egress_chain_removed's nft-fallback path.
essentials_dir="$WORKDIR/essentials"
mkdir -p "$essentials_dir"
for tool in bash grep cut tr cat basename uname mktemp head rm python3; do
  real=$(command -v "$tool" 2>/dev/null || true)
  [ -n "$real" ] && ln -sf "$real" "$essentials_dir/$tool"
done

# run_scenario <name> <case_dir_writer_function>
# The writer function receives the scenario's bin dir and populates it with
# mock nft/ufw/firewall-cmd executables (only the ones that should be
# "installed" in that scenario).
run_scenario() {
  local name=$1 writer=$2
  local bindir="$WORKDIR/$name"
  mkdir -p "$bindir"
  for f in "$essentials_dir"/*; do ln -sf "$f" "$bindir/$(basename "$f")"; done
  "$writer" "$bindir"
  local out="$WORKDIR/$name.json"
  set +e
  PATH="$bindir" bash "$SCRIPT" >"$out" 2>"$WORKDIR/$name.stderr"
  set -e
  python3 -m json.tool "$out" >/dev/null || {
    echo "::error::$name did not produce parseable JSON" >&2
    cat "$WORKDIR/$name.stderr" >&2
    exit 1
  }
  echo "$out"
}

mock() { # mock <path> <script-body>
  printf '%s\n' "$2" > "$1"
  chmod +x "$1"
}

assert_check() {
  local out=$1 id=$2 status=$3 detail=$4
  python3 - "$out" "$id" "$status" "$detail" <<'PY'
import json, sys
path, check_id, expected_status, expected_detail = sys.argv[1:]
checks = json.load(open(path, encoding="utf-8")).get("checks", [])
matches = [c for c in checks if c.get("id") == check_id]
if len(matches) != 1:
    print(f"::error::{path}: expected exactly one check id={check_id!r}, found {len(matches)}")
    raise SystemExit(1)
actual_status, actual_detail = matches[0].get("status"), matches[0].get("detail")
if actual_status != expected_status or actual_detail != expected_detail:
    print(f"::error::{path}: {check_id!r} expected {expected_status}/{expected_detail!r}, "
          f"got {actual_status}/{actual_detail!r}")
    raise SystemExit(1)
PY
}

# --- scenario A: both firewalld and ufw active, nft present -> firewalld wins ---
writer_both_active() {
  mock "$1/firewall-cmd" '#!/usr/bin/env bash
[ "$1" = "--state" ] && { echo running; exit 0; }
exit 1'
  mock "$1/ufw" '#!/usr/bin/env bash
[ "$1" = "status" ] && { echo "Status: active"; exit 0; }
exit 1'
  mock "$1/nft" '#!/usr/bin/env bash
[ "$1" = "list" ] && [ "$2" = "ruleset" ] && { echo "table inet filter {}"; exit 0; }
exit 1'
}
out=$(run_scenario both-active writer_both_active)
assert_check "$out" firewall_backend PASS nftables
assert_check "$out" firewall_provider PASS firewalld
assert_check "$out" firewall_state PASS running
assert_check "$out" firewall_rules PASS present

# --- scenario B: ufw enabled, nft present, no firewalld (AC-001 allow #2) ---
writer_ufw_only() {
  mock "$1/ufw" '#!/usr/bin/env bash
[ "$1" = "status" ] && { echo "Status: active"; exit 0; }
exit 1'
  mock "$1/nft" '#!/usr/bin/env bash
exit 1'
}
out=$(run_scenario ufw-only writer_ufw_only)
assert_check "$out" firewall_backend PASS nftables
assert_check "$out" firewall_provider PASS ufw
assert_check "$out" firewall_state PASS running

# --- scenario C: firewalld stopped, no ufw/nft (AC-001 deny #1) ---
writer_firewalld_stopped() {
  mock "$1/firewall-cmd" '#!/usr/bin/env bash
[ "$1" = "--state" ] && { echo "not running" >&2; exit 252; }
exit 1'
}
out=$(run_scenario firewalld-stopped writer_firewalld_stopped)
assert_check "$out" firewall_backend PASS firewalld
assert_check "$out" firewall_provider UNKNOWN none
assert_check "$out" firewall_state UNKNOWN inactive
assert_check "$out" firewall_rules UNKNOWN tool-absent

# --- scenario D: no managers, external non-empty nft ruleset (AC-001 deny #2) ---
writer_external_nft() {
  mock "$1/nft" '#!/usr/bin/env bash
[ "$1" = "list" ] && [ "$2" = "ruleset" ] && { echo "table inet filter {}"; exit 0; }
exit 1'
}
out=$(run_scenario external-nft writer_external_nft)
assert_check "$out" firewall_backend PASS nftables
assert_check "$out" firewall_provider UNKNOWN external
assert_check "$out" firewall_state UNKNOWN tool-absent
assert_check "$out" firewall_rules PASS present

# --- scenario E: no managers, no nft at all (AC-001 deny #3) ---
writer_none() { :; }
out=$(run_scenario none writer_none)
assert_check "$out" firewall_backend UNKNOWN unavailable
assert_check "$out" firewall_provider UNKNOWN none
assert_check "$out" firewall_state UNKNOWN tool-absent
assert_check "$out" firewall_rules UNKNOWN tool-absent

# --- scenario F: no managers, nft present, ruleset genuinely empty (AC-002 allow #2) ---
writer_empty_ruleset() {
  mock "$1/nft" '#!/usr/bin/env bash
[ "$1" = "list" ] && [ "$2" = "ruleset" ] && { echo -n ""; exit 0; }
exit 1'
}
out=$(run_scenario empty-ruleset writer_empty_ruleset)
assert_check "$out" firewall_provider UNKNOWN none
assert_check "$out" firewall_rules UNKNOWN empty-ruleset

# --- scenario G: no managers, nft present, unprivileged query (AC-002 deny #1/#3) ---
writer_permission_denied() {
  mock "$1/nft" '#!/usr/bin/env bash
[ "$1" = "list" ] && [ "$2" = "ruleset" ] && { echo "Error: Could not process rule: Operation not permitted" >&2; exit 1; }
exit 1'
}
out=$(run_scenario permission-denied writer_permission_denied)
assert_check "$out" firewall_provider UNKNOWN status-unavailable
assert_check "$out" firewall_rules UNKNOWN permission-denied

# --- scenario H: no managers, nft present, query fails for some other reason ---
writer_other_failure() {
  mock "$1/nft" '#!/usr/bin/env bash
[ "$1" = "list" ] && [ "$2" = "ruleset" ] && { echo "some transient netlink error" >&2; exit 1; }
exit 1'
}
out=$(run_scenario other-failure writer_other_failure)
assert_check "$out" firewall_provider UNKNOWN status-unavailable
assert_check "$out" firewall_rules UNKNOWN status-unavailable

# --- scenario I: ufw installed but inactive, no firewalld/nft (PR #53 table, tool-absent vs inactive) ---
writer_ufw_inactive() {
  mock "$1/ufw" '#!/usr/bin/env bash
[ "$1" = "status" ] && { echo "Status: inactive"; exit 0; }
exit 1'
}
out=$(run_scenario ufw-inactive writer_ufw_inactive)
assert_check "$out" firewall_backend PASS ufw
assert_check "$out" firewall_provider UNKNOWN none
assert_check "$out" firewall_state UNKNOWN inactive
assert_check "$out" firewall_rules UNKNOWN tool-absent

# --- scenario J: ufw installed but cannot answer (empty stdout, PR #53 status-unavailable) ---
writer_ufw_unavailable() {
  mock "$1/ufw" '#!/usr/bin/env bash
[ "$1" = "status" ] && exit 1
exit 1'
}
out=$(run_scenario ufw-unavailable writer_ufw_unavailable)
assert_check "$out" firewall_state UNKNOWN status-unavailable

# --- scenario K: residual KUBE_READY_EGRESS chain, detected via iptables -S (#44 T-016) ---
writer_egress_chain_present() {
  mock "$1/iptables" '#!/usr/bin/env bash
if [ "$1" = "-S" ] && [ "$2" = "KUBE_READY_EGRESS" ]; then
  echo "-N KUBE_READY_EGRESS"
  echo "-A KUBE_READY_EGRESS -j DROP"
  exit 0
fi
exit 1'
}
out=$(run_scenario egress-chain-present writer_egress_chain_present)
assert_check "$out" egress_chain_removed FAIL present

# --- scenario L: egress chain properly removed, detected via iptables -S (allow case) ---
writer_egress_chain_absent() {
  mock "$1/iptables" '#!/usr/bin/env bash
if [ "$1" = "-S" ] && [ "$2" = "KUBE_READY_EGRESS" ]; then
  echo "iptables: No chain/target/match by that name." >&2
  exit 1
fi
exit 1'
}
out=$(run_scenario egress-chain-absent writer_egress_chain_absent)
assert_check "$out" egress_chain_removed PASS absent

# --- scenario M: iptables present but unprivileged (must be UNKNOWN, never FAIL) ---
writer_egress_chain_permission_denied() {
  mock "$1/iptables" '#!/usr/bin/env bash
if [ "$1" = "-S" ] && [ "$2" = "KUBE_READY_EGRESS" ]; then
  echo "iptables: Permission denied (you must be root)." >&2
  exit 4
fi
exit 1'
}
out=$(run_scenario egress-chain-permission-denied writer_egress_chain_permission_denied)
assert_check "$out" egress_chain_removed UNKNOWN permission-denied

# --- scenario N: neither iptables nor nft readable -> UNKNOWN, never FAIL ---
writer_egress_chain_tool_absent() { :; }
out=$(run_scenario egress-chain-tool-absent writer_egress_chain_tool_absent)
assert_check "$out" egress_chain_removed UNKNOWN tool-absent

# --- scenario O: no iptables, nft fallback shows the chain still present ---
writer_egress_chain_nft_fallback() {
  mock "$1/nft" '#!/usr/bin/env bash
[ "$1" = "list" ] && [ "$2" = "ruleset" ] && { echo "table ip filter { chain KUBE_READY_EGRESS { } }"; exit 0; }
exit 1'
}
out=$(run_scenario egress-chain-nft-fallback writer_egress_chain_nft_fallback)
assert_check "$out" egress_chain_removed FAIL present

echo "network-firewall-detection-test.sh: all scenarios passed"
