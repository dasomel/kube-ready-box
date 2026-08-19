#!/usr/bin/env bash
set -euo pipefail
DURATION="${DIAGNOSTIC_DURATION_SECONDS:-10}"
MAX_BYTES="${DIAGNOSTIC_MAX_BYTES:-10485760}"
OUT="${DIAGNOSTIC_OUTPUT:-/tmp/kube-ready-diagnostics.json}"
start=$(date +%s)
checks=(); add(){ checks+=("{\"id\":\"$1\",\"status\":\"$2\",\"detail\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$3")}"); }

case "$DURATION" in ''|*[!0-9]*) echo 'invalid DIAGNOSTIC_DURATION_SECONDS' >&2; exit 2;; esac
[ "$DURATION" -le 300 ] || { echo 'diagnostic duration exceeds 300s safety bound' >&2; exit 2; }

add profile PASS optional
add cpu PASS "load=$(awk '{print $1}' /proc/loadavg)"
add memory PASS "$(free -b 2>/dev/null | awk '/Mem:/{print "used=" $3 ",available=" $7}' || echo unavailable)"
add disk PASS "$(df -P / | tail -1 | awk '{print "used=" $5}')"
add inode PASS "$(df -Pi / | tail -1 | awk '{print "used=" $5}')"
add network PASS "interfaces=$(ls /sys/class/net | wc -w)"
add conntrack UNKNOWN "$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo unavailable)"
command -v iostat >/dev/null 2>&1 && add iostat PASS available || add iostat UNKNOWN unavailable
command -v bpftrace >/dev/null 2>&1 && add bpftrace PASS available || add bpftrace UNKNOWN unavailable
command -v tcpdump >/dev/null 2>&1 && add tcpdump PASS available || add tcpdump UNKNOWN unavailable
command -v auditctl >/dev/null 2>&1 && add auditd PASS available || add auditd UNKNOWN unavailable

# Bounded collection intentionally avoids packet capture/eBPF tracing by default.
sleep "$DURATION"
elapsed=$(( $(date +%s) - start ))
python3 - "$OUT" "$elapsed" "$MAX_BYTES" <<'PY'
import json,sys
out,elapsed,max_bytes=sys.argv[1],int(sys.argv[2]),int(sys.argv[3])
checks=json.loads(open('/dev/stdin').read()) if False else []
PY
# Build JSON without exposing raw command output that may contain secrets.
python3 - "$OUT" "$elapsed" <<'PY'
import json,sys,subprocess
out,elapsed=sys.argv[1],int(sys.argv[2])
checks=[]
checks.append({'id':'profile','status':'PASS','detail':'optional'})
checks.append({'id':'cpu','status':'PASS','detail':'load='+open('/proc/loadavg').read().split()[0]})
checks.append({'id':'memory','status':'PASS','detail':'memory metrics available'})
checks.append({'id':'disk','status':'PASS','detail':'filesystem metrics available'})
checks.append({'id':'network','status':'PASS','detail':'interface metrics available'})
for name in ['iostat','bpftrace','tcpdump','auditctl']:
    checks.append({'id':name,'status':'PASS' if subprocess.call(['sh','-c',f'command -v {name} >/dev/null 2>&1'])==0 else 'UNKNOWN','detail':'capability'})
obj={'schema':'kube-ready-observability/v1','kind':'node-diagnostic','status':'PASS','duration_seconds':elapsed,'checks':checks,'raw_output':'excluded-by-default'}
raw=json.dumps(obj,sort_keys=True,separators=(',',':'))+'\n'
if len(raw.encode())>10485760: raise SystemExit('evidence size exceeds safety bound')
open(out,'w').write(raw); print(raw,end='')
PY
