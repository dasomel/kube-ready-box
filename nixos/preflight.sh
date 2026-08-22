#!/usr/bin/env bash
set -euo pipefail
checks=(); failures=0; unknowns=0
add(){ local id=$1 st=$2 d=$3; checks+=("{\"id\":\"$id\",\"status\":\"$st\",\"detail\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$d")}"); case "$st" in FAIL) failures=$((failures+1));; UNKNOWN) unknowns=$((unknowns+1));; esac; }

. /etc/os-release
[ "$ID" = nixos ] && add os PASS "NixOS $VERSION_ID" || add os FAIL "not NixOS"
stat -fc %T /sys/fs/cgroup 2>/dev/null | grep -q cgroup2fs && add cgroup_v2 PASS enabled || add cgroup_v2 FAIL missing
swapon --show --noheadings 2>/dev/null | grep -q . && add swap FAIL enabled || add swap PASS disabled
for m in overlay br_netfilter; do grep -q "^$m " /proc/modules 2>/dev/null && add module_$m PASS loaded || add module_$m FAIL not-loaded; done
[ -r /proc/sys/net/ipv4/ip_forward ] && [ "$(cat /proc/sys/net/ipv4/ip_forward)" = 1 ] && add ip_forward PASS 1 || add ip_forward FAIL 0
mountpoint -q /sys/fs/bpf 2>/dev/null && add bpffs PASS mounted || add bpffs UNKNOWN not-mounted
systemctl cat containerd >/dev/null 2>&1 && add containerd PASS installed || add containerd UNKNOWN not-installed
command -v runc >/dev/null && add runc PASS installed || add runc UNKNOWN missing
command -v chronyc >/dev/null && add chrony PASS installed || add chrony UNKNOWN missing
command -v iscsiadm >/dev/null && add iscsi PASS installed || add iscsi UNKNOWN missing
command -v cryptsetup >/dev/null && add cryptsetup PASS installed || add cryptsetup UNKNOWN missing
fs=$(findmnt -n -o FSTYPE / 2>/dev/null || echo unknown); case "$fs" in ext4|xfs) add filesystem PASS "$fs";; *) add filesystem UNKNOWN "$fs";; esac
if systemctl cat sshd.service >/dev/null 2>&1; then systemctl is-active --quiet sshd && add ssh PASS active || add ssh UNKNOWN inactive; else add ssh UNKNOWN missing; fi

status=PASS; [ "$failures" -gt 0 ] && status=FAIL
printf '{"schema":"kube-ready-readiness/v1","kind":"nixos-node-readiness","status":"%s","checks":[%s],"failures":%d,"unknowns":%d}\n' "$status" "$(IFS=,; echo "${checks[*]}")" "$failures" "$unknowns"
[ "$status" = PASS ]
