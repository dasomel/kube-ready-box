#!/usr/bin/env bash
set -euo pipefail

cat >/usr/local/bin/k8s-node-preflight <<'VALIDATOR'
#!/usr/bin/env bash
set -u

mode="${1:-text}"
strict_runtime="${STRICT_RUNTIME:-0}"
failed=0
unknown=0

essential_packages=(open-iscsi cryptsetup dmsetup)

result_json(){
  local name="$1" status="$2" detail="$3"
  python3 - "$name" "$status" "$detail" <<'PY'
import json,sys
print(json.dumps({'name':sys.argv[1],'status':sys.argv[2],'detail':sys.argv[3]},sort_keys=True,separators=(',',':')))
PY
}
check(){
  local name="$1" status="$2" detail="$3"
  case "$status" in FAIL) failed=$((failed+1));; UNKNOWN) unknown=$((unknown+1));; esac
  result_json "$name" "$status" "$detail" >>"$report_file"
}

report_file=$(mktemp)
trap 'rm -f "$report_file"' EXIT

# cgroup v2
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then check cgroup_v2 PASS 'cgroup v2 mounted'; else check cgroup_v2 FAIL 'cgroup v2 not detected'; fi

# swap
if swapon --noheadings --show 2>/dev/null | grep -q .; then check swap FAIL 'swap is enabled'; else check swap PASS 'swap disabled'; fi

# kernel modules
for mod in overlay br_netfilter iscsi_tcp; do
  if lsmod 2>/dev/null | awk '{print $1}' | grep -qx "$mod" || [ -d "/sys/module/$mod" ]; then
    check "module_$mod" PASS 'loaded'
  else
    check "module_$mod" FAIL 'not loaded'
  fi
done

# bpffs
if mountpoint -q /sys/fs/bpf 2>/dev/null; then check bpffs PASS 'mounted'; else check bpffs FAIL 'not mounted'; fi

# Kubernetes sysctls
for pair in net.ipv4.ip_forward=1 net.bridge.bridge-nf-call-iptables=1 net.bridge.bridge-nf-call-ip6tables=1; do
  key=${pair%%=*}; expected=${pair##*=}; actual=$(sysctl -n "$key" 2>/dev/null || true)
  if [ "$actual" = "$expected" ]; then check "sysctl_${key//./_}" PASS "$actual"; else check "sysctl_${key//./_}" FAIL "expected=$expected actual=${actual:-missing}"; fi
done

# filesystem
root_fs=$(findmnt -n -o FSTYPE / 2>/dev/null || true)
case "$root_fs" in ext4|xfs) check root_filesystem PASS "$root_fs";; '') check root_filesystem UNKNOWN 'root filesystem unavailable';; *) check root_filesystem UNKNOWN "unsupported root filesystem=$root_fs";; esac

# time sync
if command -v chronyc >/dev/null 2>&1; then
  if chronyc tracking 2>/dev/null | grep -q '^Reference ID'; then
    check chrony PASS 'chrony tracking available'
  else
    check chrony FAIL 'chrony tracking unavailable'
  fi
else
  check chrony FAIL 'chrony not installed'
fi

# security baseline
if command -v aa-status >/dev/null 2>&1; then
  if aa-status --enabled >/dev/null 2>&1; then check apparmor PASS 'enabled'; else check apparmor UNKNOWN 'not enabled'; fi
else check apparmor UNKNOWN 'aa-status unavailable'; fi

if command -v auditctl >/dev/null 2>&1; then
  if auditctl -s 2>/dev/null | grep -q '^enabled[[:space:]]*=[[:space:]]*1'; then check auditd PASS 'enabled'; else check auditd UNKNOWN 'not enabled'; fi
else check auditd UNKNOWN 'auditctl unavailable'; fi

# CSI prerequisites
for pkg in "${essential_packages[@]}"; do
  if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed'; then check "package_$pkg" PASS 'installed'; else check "package_$pkg" FAIL 'missing'; fi
done

# container runtime
if command -v containerd >/dev/null 2>&1 || [ -x /usr/bin/containerd ]; then
  if [ -f /etc/containerd/config.toml ] && grep -Eq 'SystemdCgroup[[:space:]]*=[[:space:]]*true' /etc/containerd/config.toml; then
    check containerd_systemdcgroup PASS 'enabled'
  else
    check containerd_systemdcgroup FAIL 'SystemdCgroup=true not found'
  fi
else
  if [ "$strict_runtime" = "1" ]; then check containerd_runtime FAIL 'containerd not installed'; else check containerd_runtime UNKNOWN 'containerd not installed'; fi
fi

# nofile
nofile=$(ulimit -n 2>/dev/null || echo 0)
if [ "$nofile" -ge 1048576 ] 2>/dev/null; then check nofile PASS "$nofile"; else check nofile UNKNOWN "current=$nofile"; fi

if [ "$mode" = json ]; then
  python3 - "$report_file" "$failed" "$unknown" "$strict_runtime" <<'PY'
import json,sys
records=[json.loads(x) for x in open(sys.argv[1]) if x.strip()]
failed=int(sys.argv[2]); unknown=int(sys.argv[3]); strict=int(sys.argv[4])
obj={'schema':'kube-ready-node-preflight/v1','status':'FAIL' if failed else 'PASS','failures':failed,'unknowns':unknown,'strictRuntime':bool(strict),'checks':records}
print(json.dumps(obj,sort_keys=True,separators=(',',':')))
PY
else
  echo '=== Kubernetes node preflight ==='
  cat "$report_file"
  echo "failures=$failed unknowns=$unknown strict_runtime=$strict_runtime"
fi

[ "$failed" -eq 0 ]
VALIDATOR

chmod 0755 /usr/local/bin/k8s-node-preflight
/usr/local/bin/k8s-node-preflight json >/etc/vagrant-box/k8s-node-preflight-baseline.json || true
