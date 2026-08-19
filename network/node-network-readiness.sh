#!/usr/bin/env bash
set -euo pipefail
checks=(); failures=0; unknowns=0
add(){ local id=$1 st=$2 d=$3; checks+=("{\"id\":\"$id\",\"status\":\"$st\",\"detail\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$d")}"); [ "$st" = FAIL ] && failures=$((failures+1)); [ "$st" = UNKNOWN ] && unknowns=$((unknowns+1)); }

for p in /proc/sys/net/ipv4/ip_forward /proc/sys/net/ipv6/conf/all/forwarding; do
  id=$(basename "$p"); [ -r "$p" ] && [ "$(cat "$p")" = 1 ] && add "$id" PASS 1 || add "$id" FAIL missing-or-zero
done

[ -r /proc/sys/net/bridge/bridge-nf-call-iptables ] && add bridge_nf PASS "$(cat /proc/sys/net/bridge/bridge-nf-call-iptables)" || add bridge_nf UNKNOWN unavailable

if command -v nft >/dev/null 2>&1; then
  rules=$(nft list ruleset 2>/dev/null || true); add firewall_backend PASS nftables
  [ -n "$rules" ] && add firewall_rules PASS present || add firewall_rules UNKNOWN empty
elif command -v firewall-cmd >/dev/null 2>&1; then add firewall_backend PASS firewalld; firewall-cmd --state >/dev/null 2>&1 && add firewall_state PASS running || add firewall_state UNKNOWN inactive
else add firewall_backend UNKNOWN unavailable; fi

if [ -r /proc/sys/net/netfilter/nf_conntrack_max ]; then
  max=$(cat /proc/sys/net/netfilter/nf_conntrack_max); count=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo 0)
  add conntrack PASS "count=$count max=$max"
else add conntrack UNKNOWN unavailable; fi

for iface in $(ls /sys/class/net); do
  [ "$iface" = lo ] && continue
  mtu=$(cat "/sys/class/net/$iface/mtu" 2>/dev/null || echo unknown)
  add "mtu_$iface" PASS "$mtu"
done

if command -v resolvectl >/dev/null 2>&1; then resolvectl status >/dev/null 2>&1 && add dns_resolver PASS resolvectl || add dns_resolver UNKNOWN unavailable; elif [ -s /etc/resolv.conf ]; then add dns_resolver PASS resolv.conf; else add dns_resolver UNKNOWN missing; fi

if command -v ip >/dev/null 2>&1; then add routing PASS "$(ip route show | wc -l) routes"; else add routing UNKNOWN ip-command-missing; fi

if command -v ethtool >/dev/null 2>&1; then add ethtool PASS available; else add ethtool UNKNOWN unavailable; fi

status=PASS; [ "$failures" -gt 0 ] && status=FAIL
printf '{"schema":"kube-ready-network/v1","kind":"node-network-readiness","status":"%s","architecture":"%s","checks":[%s],"failures":%d,"unknowns":%d}\n' "$status" "$(uname -m)" "$(IFS=,; echo "${checks[*]}")" "$failures" "$unknowns"
[ "$status" = PASS ]
