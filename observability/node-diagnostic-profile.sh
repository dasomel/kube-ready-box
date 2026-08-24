#!/usr/bin/env bash
set -euo pipefail
DURATION="${DIAGNOSTIC_DURATION_SECONDS:-10}"
MAX_BYTES="${DIAGNOSTIC_MAX_BYTES:-10485760}"
OUT="${DIAGNOSTIC_OUTPUT:-/tmp/kube-ready-diagnostics.json}"
start=$(date +%s)

checks=()
add(){ checks+=("{\"id\":\"$1\",\"status\":\"$2\",\"detail\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$3")}"); }

# 진단 도구를 실행해 버전을 물어보면(예: --version) 도구에 따라 예기치 않은
# 부작용/hang 위험이 있다(특히 iftop/nethogs 류는 원래 root+라이브 캡처 용도).
# dpkg 패키지 버전만 조회하면 어떤 진단 바이너리도 실행하지 않고 실제 버전을
# 얻을 수 있다.
tool_check(){
  local id="$1" bin="$2" pkg="$3" ver
  if command -v "$bin" >/dev/null 2>&1; then
    ver=$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || true)
    add "$id" PASS "${ver:-available}"
  else
    add "$id" UNKNOWN unavailable
  fi
}

case "$DURATION" in ''|*[!0-9]*) echo 'invalid DIAGNOSTIC_DURATION_SECONDS' >&2; exit 2;; esac
[ "$DURATION" -le 300 ] || { echo 'diagnostic duration exceeds 300s safety bound' >&2; exit 2; }

add profile PASS optional

if [ -r /etc/os-release ]; then
  os_id=$(grep -m1 '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"') || true
  [ -n "$os_id" ] && add os_id PASS "$os_id" || add os_id UNKNOWN unavailable
else
  add os_id UNKNOWN unavailable
fi
add architecture PASS "$(uname -m)"

add cpu PASS "load=$(awk '{print $1}' /proc/loadavg)"
mem_detail=$(command -v free >/dev/null 2>&1 && free -b 2>/dev/null | awk '/Mem:/{print "used="$3",available="$7}' || true)
[ -n "$mem_detail" ] && add memory PASS "$mem_detail" || add memory UNKNOWN unavailable
add disk PASS "$(df -P / | tail -1 | awk '{print "used="$5}')"
add inode PASS "$(df -Pi / | tail -1 | awk '{print "used="$5}')"
add network_interfaces PASS "count=$(ls /sys/class/net | wc -w)"

# 인터페이스별이 아니라 lo 를 제외한 합계 — 개별 인터페이스 상세는
# network/node-network-readiness.sh(mtu_<iface>)가 이미 담당한다.
net_summary=$(awk 'NR>2 && $1!~/^lo:/{rx+=$2; rxe+=$4; rxd+=$5; tx+=$10; txe+=$12; txd+=$13} END{printf "rx_bytes=%d,rx_errors=%d,rx_drop=%d,tx_bytes=%d,tx_errors=%d,tx_drop=%d",rx+0,rxe+0,rxd+0,tx+0,txe+0,txd+0}' /proc/net/dev 2>/dev/null || true)
[ -n "$net_summary" ] && add network_io PASS "$net_summary" || add network_io UNKNOWN unavailable

if [ -r /proc/sys/net/netfilter/nf_conntrack_count ]; then
  add conntrack PASS "$(cat /proc/sys/net/netfilter/nf_conntrack_count)"
else
  add conntrack UNKNOWN unavailable
fi

for spec in \
  "sysstat:iostat:sysstat" \
  "iotop:iotop:iotop" \
  "iftop:iftop:iftop" \
  "nload:nload:nload" \
  "nethogs:nethogs:nethogs" \
  "dool:dool:dool" \
  "bpftrace:bpftrace:bpftrace" \
  "bpfcc:opensnoop-bpfcc:bpfcc-tools" \
  "tcpdump:tcpdump:tcpdump" \
  "nmap:nmap:nmap" \
  "ethtool:ethtool:ethtool" \
  "auditd:auditctl:auditd"
do
  IFS=: read -r id bin pkg <<<"$spec"
  tool_check "$id" "$bin" "$pkg"
done

# Bounded collection intentionally avoids packet capture/eBPF tracing by default.
sleep "$DURATION"
elapsed=$(( $(date +%s) - start ))

# raw_output 은 항상 "excluded-by-default" 로 고정한다 — checks[] 는 숫자/버전
# 문자열만 담고 tcpdump/audit 원본 출력을 절대 넣지 않으므로, redaction 대상이
# 될 raw output 자체가 애초에 수집되지 않는다.
#
# checks[] 를 이어붙인 문자열을 argv 로 그대로 넘기면 (도구 버전 문자열이
# 늘어날수록) 실제 CI 러너에서 ARG_MAX 초과로 죽을 수 있다 -- 이 저장소가
# tools/sbom-license-gate.sh 와 tools/kube-ready-contracts.sh 에서 이미
# 겪은 것과 같은 버그 유형이라 여기도 파일로 넘긴다.
checks_file=$(mktemp)
printf '%s' "$(IFS=,; echo "${checks[*]}")" > "$checks_file"
python3 - "$OUT" "$elapsed" "$MAX_BYTES" "$checks_file" <<'PY'
import json,sys
out, elapsed, max_bytes, checks_file = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
with open(checks_file) as f:
    raw_checks = f.read()
checks = json.loads('[' + raw_checks + ']') if raw_checks else []
obj = {
    'schema': 'kube-ready-observability/v1',
    'kind': 'node-diagnostic',
    'status': 'PASS',
    'duration_seconds': elapsed,
    'checks': checks,
    'raw_output': 'excluded-by-default',
}
raw = json.dumps(obj, sort_keys=True, separators=(',', ':')) + '\n'
if len(raw.encode()) > max_bytes:
    raise SystemExit(f'evidence size {len(raw.encode())} exceeds configured bound {max_bytes}')
open(out, 'w').write(raw)
print(raw, end='')
PY
rm -f "$checks_file"
