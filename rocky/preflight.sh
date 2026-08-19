#!/usr/bin/env bash
set -euo pipefail
SCHEMA=kube-ready-readiness/v1
checks=(); failures=0; unknowns=0
add(){ local id=$1 st=$2 d=$3; checks+=("{\"id\":\"$id\",\"status\":\"$st\",\"detail\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$d")}"); [ "$st" = FAIL ] && failures=$((failures+1)); [ "$st" = UNKNOWN ] && unknowns=$((unknowns+1)); }

. /etc/os-release
[[ "$ID" = rocky ]] && add os PASS "$PRETTY_NAME" || add os FAIL "not Rocky Linux"
selinux=$(getenforce 2>/dev/null || echo unavailable); case "$selinux" in Enforcing) add selinux PASS "$selinux";; Permissive|Disabled) add selinux FAIL "$selinux";; *) add selinux UNKNOWN "$selinux";; esac
command -v firewall-cmd >/dev/null && add firewalld PASS installed || add firewalld UNKNOWN unavailable
systemctl is-active --quiet NetworkManager && add networkmanager PASS active || add networkmanager UNKNOWN inactive
stat -fc %T /sys/fs/cgroup 2>/dev/null | grep -q cgroup2fs && add cgroup_v2 PASS enabled || add cgroup_v2 FAIL missing
swapon --show --noheadings 2>/dev/null | grep -q . && add swap FAIL enabled || add swap PASS disabled
for m in overlay br_netfilter; do grep -q "^$m " /proc/modules 2>/dev/null && add module_$m PASS loaded || add module_$m FAIL not-loaded; done
for p in /proc/sys/net/ipv4/ip_forward /proc/sys/net/bridge/bridge-nf-call-iptables; do [ -r "$p" ] && [ "$(cat "$p")" = 1 ] && add "sysctl_$(basename "$p")" PASS 1 || add "sysctl_$(basename "$p")" FAIL missing-or-zero; done
mountpoint -q /sys/fs/bpf 2>/dev/null && add bpffs PASS mounted || add bpffs UNKNOWN not-mounted
if systemctl cat containerd >/dev/null 2>&1; then grep -Rqs 'SystemdCgroup[[:space:]]*=[[:space:]]*true' /etc/containerd 2>/dev/null && add containerd_systemdcgroup PASS enabled || add containerd_systemdcgroup FAIL disabled; else add containerd_systemdcgroup UNKNOWN not-installed; fi
command -v chronyc >/dev/null && add chrony PASS installed || add chrony UNKNOWN missing
for x in iscsiadm cryptsetup dmsetup; do command -v "$x" >/dev/null && add csi_$x PASS present || add csi_$x UNKNOWN missing; done
fs=$(findmnt -n -o FSTYPE / 2>/dev/null || echo unknown); case "$fs" in xfs|ext4) add filesystem PASS "$fs";; *) add filesystem UNKNOWN "$fs";; esac

if [[ "$VERSION_ID" == 10* ]]; then
  if uname -m | grep -Eq 'x86_64|amd64'; then
    flags=$(grep -m1 '^flags' /proc/cpuinfo 2>/dev/null || true)
    for f in avx avx2 bmi1 bmi2 f16c; do echo "$flags" | grep -qw "$f" || { add rocky10_x86_64_v3 FAIL "missing $f"; break; }; done
    [ "${#checks[@]}" -gt 0 ] && ! printf '%s\n' "${checks[@]}" | grep -q 'rocky10_x86_64_v3' && add rocky10_x86_64_v3 PASS cpu-flags
  else add rocky10_x86_64_v3 UNKNOWN "non-x86_64 architecture"; fi
else add rocky10_x86_64_v3 UNKNOWN "not Rocky 10"; fi

status=PASS; [ "$failures" -gt 0 ] && status=FAIL
printf '{"schema":"%s","kind":"rocky-node-readiness","status":"%s","os":"%s","version":"%s","architecture":"%s","failures":%d,"unknowns":%d,"checks":[%s]}\n' "$SCHEMA" "$status" "$ID" "$VERSION_ID" "$(uname -m)" "$failures" "$unknowns" "$(IFS=,; echo "${checks[*]}")"
[ "$status" = PASS ]
