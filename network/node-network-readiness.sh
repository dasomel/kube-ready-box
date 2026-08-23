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

if command -v nft >/dev/null 2>&1; then
  rules=$(nft list ruleset 2>/dev/null || true); add firewall_backend PASS nftables
  [ -n "$rules" ] && add firewall_rules PASS present || add firewall_rules UNKNOWN empty
elif command -v firewall-cmd >/dev/null 2>&1; then add firewall_backend PASS firewalld; firewall-cmd --state >/dev/null 2>&1 && add firewall_state PASS running || add firewall_state UNKNOWN inactive
else add firewall_backend UNKNOWN unavailable; fi

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
