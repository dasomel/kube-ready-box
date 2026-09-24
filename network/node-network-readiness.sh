#!/usr/bin/env bash
set -euo pipefail
checks=(); failures=0; unknowns=0
add(){ local id=$1 st=$2 d=$3; checks+=("{\"id\":\"$id\",\"status\":\"$st\",\"detail\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$d")}"); case "$st" in FAIL) failures=$((failures+1));; UNKNOWN) unknowns=$((unknowns+1));; esac; }

if [ -r /etc/os-release ]; then
  os_id=$(grep -m1 '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"') || true
  [ -n "$os_id" ] && add os_id PASS "$os_id" || add os_id UNKNOWN missing
else
  add os_id UNKNOWN missing
fi

for p in /proc/sys/net/ipv4/ip_forward /proc/sys/net/ipv6/conf/all/forwarding; do
  id=$(basename "$p"); [ -r "$p" ] && [ "$(cat "$p")" = 1 ] && add "$id" PASS 1 || add "$id" FAIL missing-or-zero
done

[ -r /proc/sys/net/bridge/bridge-nf-call-iptables ] && add bridge_nf PASS "$(cat /proc/sys/net/bridge/bridge-nf-call-iptables)" || add bridge_nf UNKNOWN unavailable

# firewall_backend: legacy packet-filter-backend precedence (nft > firewalld > ufw),
# unchanged for existing consumers -- see firewall_provider below for the manager
# that actually owns enforcement (#44 C-01: firewalld/ufw are nft-backed and would
# otherwise be masked as "nftables" here).
if command -v nft >/dev/null 2>&1; then add firewall_backend PASS nftables
elif command -v firewall-cmd >/dev/null 2>&1; then add firewall_backend PASS firewalld
elif command -v ufw >/dev/null 2>&1; then add firewall_backend PASS ufw
else add firewall_backend UNKNOWN unavailable; fi

# firewall-cmd --state prints "running" on stdout but "not running" on stderr
# (exit 252, verified on rockylinux:9), so both streams are read.
fw_state=""; command -v firewall-cmd >/dev/null 2>&1 && fw_state=$(firewall-cmd --state 2>&1 | head -n1 || true)
firewalld_running=0; [ "$fw_state" = running ] && firewalld_running=1
ufw_status=""; command -v ufw >/dev/null 2>&1 && ufw_status=$(ufw status 2>/dev/null | head -n1 || echo "")
ufw_active=0; [ "$ufw_status" = "Status: active" ] && ufw_active=1

nft_rc=1; nft_rules=""; nft_err=""
if command -v nft >/dev/null 2>&1; then
  # On failure, re-run once for stderr only: no temp file that could fail or leak.
  # LC_ALL=C keeps nft_err's text locale-independent -- it's classified by
  # substring below and by egress_chain_removed's nft fallback.
  nft_rules=$(LC_ALL=C nft list ruleset 2>/dev/null) && nft_rc=0 || {
    nft_rc=$?; nft_err=$(LC_ALL=C nft list ruleset 2>&1 >/dev/null || true); }
fi

# firewall_provider (#44 D-a): name the manager that actually owns enforcement --
# check firewalld/ufw before raw nft. Precedence: firewalld running > ufw active >
# a non-empty external nft ruleset (UNKNOWN, never a nftables PASS) > empty/absent.
if [ "$firewalld_running" = 1 ]; then add firewall_provider PASS firewalld
elif [ "$ufw_active" = 1 ]; then add firewall_provider PASS ufw
elif command -v nft >/dev/null 2>&1; then
  if [ "$nft_rc" -eq 0 ]; then
    [ -n "$nft_rules" ] && add firewall_provider UNKNOWN external || add firewall_provider UNKNOWN none
  else
    add firewall_provider UNKNOWN status-unavailable
  fi
else add firewall_provider UNKNOWN none; fi

# firewall_state (#44 D-b): always emitted, for the active provider or else the
# highest-precedence installed manager (firewalld > ufw). PR #53's ufw table
# (active/inactive/empty-stdout/other) is unchanged.
if [ "$firewalld_running" = 1 ] || [ "$ufw_active" = 1 ]; then
  add firewall_state PASS running
elif command -v firewall-cmd >/dev/null 2>&1; then
  case "$fw_state" in
    "not running") add firewall_state UNKNOWN inactive ;;
    *) add firewall_state UNKNOWN status-unavailable ;;
  esac
elif command -v ufw >/dev/null 2>&1; then
  # ufw reports its failures on stderr and leaves stdout empty (e.g. it cannot
  # read the ruleset without privileges), so an empty result here means "ufw
  # could not answer", not "no firewall". Say which one it is -- an UNKNOWN
  # carrying an empty detail is unactionable evidence.
  case "$ufw_status" in
    "Status: inactive") add firewall_state UNKNOWN inactive ;;
    "") add firewall_state UNKNOWN status-unavailable ;;
    *) add firewall_state UNKNOWN "$ufw_status" ;;
  esac
else add firewall_state UNKNOWN tool-absent; fi

# firewall_rules (#44 D-c/C-02): the raw nft ruleset, independent of which manager
# owns it -- distinguishes an absent tool, a permission-denied query, any other
# query failure, a deliberately empty ruleset, and a populated one.
if ! command -v nft >/dev/null 2>&1; then
  add firewall_rules UNKNOWN tool-absent
elif [ "$nft_rc" -eq 0 ]; then
  [ -n "$nft_rules" ] && add firewall_rules PASS present || add firewall_rules UNKNOWN empty-ruleset
else
  case "$nft_err" in
    *"Operation not permitted"*|*"Permission denied"*) add firewall_rules UNKNOWN permission-denied ;;
    *) add firewall_rules UNKNOWN status-unavailable ;;
  esac
fi

# egress_chain_removed (#44 REQ-007/T-016): packer/scripts/00-egress-restrict.sh
# creates the build-only KUBE_READY_EGRESS chain via `iptables -N`, and
# 99-cleanup.sh removes it the same way -- this proves it stayed removed on a
# provisioned/booted node. Queried with `iptables -S <chain>` (the tool the
# chain was actually created with: exits non-zero with "No chain/target/match
# by that name" when absent, the expected/allow state) rather than nft, since
# an nft-only view can miss a chain built through the legacy iptables
# backend. Falls back to the nft ruleset already queried above only when
# iptables itself cannot answer. Never FAILs when neither tool is readable.
#
# LC_ALL=C forces that "No chain/target/match by that name" message (and
# every other iptables/nft message classified below) to a fixed, English
# string regardless of the host's locale: a translated locale would
# otherwise either fail to match the absent-chain text (masking a real
# absent chain as an unhelpful UNKNOWN) or, if some *other* failure's
# translated text happened to coincide with a different branch's substring,
# misclassify it. The verdict is still anchored on the exit code first
# (0 = present, matching iptables -S's own contract) and the C-locale text
# only disambiguates *why* a non-zero exit happened.
if command -v iptables >/dev/null 2>&1; then
  ipt_egress_out=$(LC_ALL=C iptables -S KUBE_READY_EGRESS 2>&1) && ipt_egress_rc=0 || ipt_egress_rc=$?
  if [ "$ipt_egress_rc" -eq 0 ]; then
    add egress_chain_removed FAIL present
  else
    case "$ipt_egress_out" in
      *"No chain/target/match by that name"*) add egress_chain_removed PASS absent ;;
      *"Permission denied"*|*"Operation not permitted"*) add egress_chain_removed UNKNOWN permission-denied ;;
      *) add egress_chain_removed UNKNOWN status-unavailable ;;
    esac
  fi
elif command -v nft >/dev/null 2>&1; then
  if [ "$nft_rc" -eq 0 ]; then
    if printf '%s' "$nft_rules" | LC_ALL=C grep -q 'KUBE_READY_EGRESS'; then
      add egress_chain_removed FAIL present
    else
      add egress_chain_removed PASS absent
    fi
  else
    case "$nft_err" in
      *"Operation not permitted"*|*"Permission denied"*) add egress_chain_removed UNKNOWN permission-denied ;;
      *) add egress_chain_removed UNKNOWN status-unavailable ;;
    esac
  fi
else
  add egress_chain_removed UNKNOWN tool-absent
fi

if command -v iptables >/dev/null 2>&1; then
  # --display lists the whole alternatives registry (both entries always
  # appear), so a substring match on it can name the wrong backend. --query's
  # "Value:" line names only the currently active link.
  ipt_active=$(update-alternatives --query iptables 2>/dev/null | awk '/^Value:/{print $2; exit}') || true
  if [ -z "$ipt_active" ]; then
    ipt_active=$(readlink -f "$(command -v iptables)" 2>/dev/null) || true
  fi
  case "$ipt_active" in
    *legacy*) ipt_backend=iptables-legacy ;;
    *nft*) ipt_backend=iptables-nft ;;
    *) ipt_backend="" ;;
  esac
  [ -n "$ipt_backend" ] && add iptables_backend PASS "$ipt_backend" || add iptables_backend UNKNOWN indeterminate
else
  add iptables_backend UNKNOWN iptables-not-found
fi

if [ -r /proc/sys/net/netfilter/nf_conntrack_max ]; then
  max=$(cat /proc/sys/net/netfilter/nf_conntrack_max); count=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo 0)
  add conntrack PASS "count=$count max=$max"
  if [ "$max" -gt 0 ]; then pct=$(( count * 100 / max )); else pct=0; fi
  if [ "$max" -gt 0 ] && [ "$pct" -gt 80 ]; then add conntrack_pressure FAIL "${pct}%"; else add conntrack_pressure PASS "${pct}%"; fi
else add conntrack UNKNOWN unavailable; fi

for ifpath in /sys/class/net/*; do
  [ -e "$ifpath" ] || continue
  iface=$(basename "$ifpath")
  if [ "$iface" = lo ]; then continue; fi
  mtu=$(cat "/sys/class/net/$iface/mtu" 2>/dev/null || echo unknown)
  add "mtu_$iface" PASS "$mtu"
done

if command -v ip >/dev/null 2>&1; then
  v4_global=$(ip -4 -o addr show scope global 2>/dev/null) || true
  v6_global=$(ip -6 -o addr show scope global 2>/dev/null) || true
  if [ -n "$v4_global" ] && [ -n "$v6_global" ]; then add dual_stack PASS dual-stack
  elif [ -n "$v4_global" ]; then add dual_stack PASS ipv4-only
  elif [ -n "$v6_global" ]; then add dual_stack PASS ipv6-only
  else add dual_stack UNKNOWN no-global-address-detected
  fi
else
  add dual_stack UNKNOWN ip-command-missing
fi

if command -v resolvectl >/dev/null 2>&1; then resolvectl status >/dev/null 2>&1 && add dns_resolver PASS resolvectl || add dns_resolver UNKNOWN unavailable; elif [ -s /etc/resolv.conf ]; then add dns_resolver PASS resolv.conf; else add dns_resolver UNKNOWN missing; fi

if command -v ip >/dev/null 2>&1; then add routing PASS "$(ip route show | wc -l) routes"; else add routing UNKNOWN ip-command-missing; fi

if command -v ethtool >/dev/null 2>&1; then add ethtool PASS available; else add ethtool UNKNOWN unavailable; fi

status=PASS; [ "$failures" -gt 0 ] && status=FAIL
printf '{"schema":"kube-ready-network/v1","kind":"node-network-readiness","status":"%s","architecture":"%s","checks":[%s],"failures":%d,"unknowns":%d}\n' "$status" "$(uname -m)" "$(IFS=,; echo "${checks[*]}")" "$failures" "$unknowns"
[ "$status" = PASS ]
