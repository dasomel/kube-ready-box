#!/usr/bin/env bash
set -euo pipefail

checks=()
failures=0
unknowns=0

json_string() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  # Remaining C0 control characters cannot be expressed with bash substitution
  # escapes; drop them so the evidence JSON stays parseable for any detail text.
  value=$(printf '%s' "$value" | tr -d '\000-\010\013\014\016-\037')
  printf '"%s"' "$value"
}

add() {
  local id=$1 status=$2 detail=$3
  checks+=("{\"id\":\"$id\",\"status\":\"$status\",\"detail\":$(json_string "$detail")}")
  case "$status" in
    FAIL) failures=$((failures + 1));;
    UNKNOWN) unknowns=$((unknowns + 1));;
  esac
}

sysctl_check() {
  local id=$1 path=$2 expected=${3:-}
  if [ ! -r "$path" ]; then
    add "$id" UNKNOWN missing
  elif [ -n "$expected" ] && [ "$(cat "$path")" != "$expected" ]; then
    add "$id" FAIL "$(cat "$path")"
  else
    add "$id" PASS "$(cat "$path")"
  fi
}

if [ -r /etc/os-release ]; then
  . /etc/os-release
fi

kernel=$(uname -r)
architecture=$(uname -m)
provider=${VAGRANT_PROVIDER:-${PROVIDER:-unknown}}
root_filesystem=$(findmnt -n -o FSTYPE / 2>/dev/null || echo unknown)

[ "${ID:-}" = nixos ] && add os PASS "NixOS ${VERSION_ID:-unknown}" || add os FAIL "not NixOS"
[ -r /etc/os-release ] && add os_id PASS "${ID:-unknown}" || add os_id UNKNOWN "/etc/os-release missing"
add architecture PASS "$architecture"
stat -fc %T /sys/fs/cgroup 2>/dev/null | grep -q cgroup2fs && add cgroup_v2 PASS enabled || add cgroup_v2 FAIL missing
swapon --show --noheadings 2>/dev/null | grep -q . && add swap FAIL enabled || add swap PASS disabled

for module in overlay br_netfilter; do
  grep -q "^$module " /proc/modules 2>/dev/null && add "module_$module" PASS loaded || add "module_$module" FAIL not-loaded
done
grep -q '^iscsi_tcp ' /proc/modules 2>/dev/null && add module_iscsi_tcp PASS loaded || add module_iscsi_tcp UNKNOWN not-loaded

sysctl_check sysctl_ip_forward /proc/sys/net/ipv4/ip_forward 1
sysctl_check sysctl_bridge_nf_call_iptables /proc/sys/net/bridge/bridge-nf-call-iptables 1
sysctl_check sysctl_bridge_nf_call_ip6tables /proc/sys/net/bridge/bridge-nf-call-ip6tables 1
sysctl_check network_nf_conntrack_max /proc/sys/net/netfilter/nf_conntrack_max
sysctl_check network_tcp_syncookies /proc/sys/net/ipv4/tcp_syncookies
mountpoint -q /sys/fs/bpf 2>/dev/null && add bpffs PASS mounted || add bpffs UNKNOWN not-mounted

if systemctl cat containerd >/dev/null 2>&1; then
  grep -Rqs 'SystemdCgroup[[:space:]]*=[[:space:]]*true' /etc/containerd 2>/dev/null && add containerd_systemdcgroup PASS enabled || add containerd_systemdcgroup FAIL not-enabled
else
  add containerd_systemdcgroup UNKNOWN containerd-not-installed
fi
for runtime in runc ctr; do command -v "$runtime" >/dev/null 2>&1 && add "runtime_$runtime" PASS installed || add "runtime_$runtime" UNKNOWN missing; done

if command -v chronyc >/dev/null 2>&1; then
  chronyc tracking 2>/dev/null | grep -Eq 'Leap status[[:space:]]*:[[:space:]]*Normal' && add time_sync PASS synchronized || add time_sync UNKNOWN chrony-not-synchronized
else
  add time_sync UNKNOWN chronyc-missing
fi
for dependency in iscsiadm cryptsetup dmsetup; do command -v "$dependency" >/dev/null 2>&1 && add "csi_$dependency" PASS installed || add "csi_$dependency" UNKNOWN missing; done

# Enabled/disabled, not bare module-directory existence (#44 C-06/T-021):
# a loaded-but-disabled module previously reported PASS.
if aa_state=$(cat /sys/module/apparmor/parameters/enabled 2>/dev/null); then
  case "$aa_state" in
    Y) add apparmor PASS enabled ;;
    N) add apparmor FAIL disabled ;;
    *) add apparmor UNKNOWN "unexpected-value:$aa_state" ;;
  esac
else
  add apparmor UNKNOWN facility-absent
fi
if [ -r /proc/self/status ] && grep -q '^Seccomp:' /proc/self/status; then
  add seccomp PASS "kernel-interface mode=$(awk '/^Seccomp:/ { print $2 }' /proc/self/status)"
else
  add seccomp UNKNOWN facility-absent
fi
ulimit_n=$(ulimit -n)
[ "$ulimit_n" -ge 65536 ] && add nofile PASS "$ulimit_n" || add nofile UNKNOWN "$ulimit_n below-65536"

case "$root_filesystem" in ext4|xfs) add filesystem PASS "$root_filesystem";; *) add filesystem UNKNOWN "$root_filesystem";; esac
if systemctl cat sshd.service >/dev/null 2>&1; then systemctl is-active --quiet sshd && add ssh PASS active || add ssh UNKNOWN inactive; else add ssh UNKNOWN missing; fi

status=PASS
[ "$failures" -gt 0 ] && status=FAIL
checks_json=$(IFS=,; echo "${checks[*]}")
printf '{"schema":"kube-ready-readiness/v1","kind":"nixos-node-readiness","status":"%s","os":{"id":%s,"version":%s},"kernel":%s,"architecture":%s,"provider":%s,"root_filesystem":%s,"checks":[%s],"failures":%d,"unknowns":%d}\n' \
  "$status" "$(json_string "${ID:-unknown}")" "$(json_string "${VERSION_ID:-unknown}")" \
  "$(json_string "$kernel")" "$(json_string "$architecture")" "$(json_string "$provider")" \
  "$(json_string "$root_filesystem")" "$checks_json" "$failures" "$unknowns"
[ "$status" = PASS ]
