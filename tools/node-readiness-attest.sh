#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

SCHEMA="kube-ready-readiness/v1"
OUT="${READINESS_OUTPUT:-/etc/vagrant-box/node-readiness.json}"
STRICT="${STRICT_READINESS:-0}"
EXPECTED_K8S="${KUBERNETES_VERSION:-}"
EXPECTED_RUNTIME="${CONTAINERD_VERSION:-}"
FAILURES=0
UNKNOWN=0
checks=()

json_escape() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip()))'; }
add() {
  local id="$1" status="$2" detail="$3"
  checks+=("$(printf '%s' "$detail" | json_escape | sed 's/^/\"/; s/$/\"/' | sed "s/\\\"/\"/g")")"
  # replace the above string with a compact JSON object safely
  checks[${#checks[@]}-1]="{\"id\":\"$id\",\"status\":\"$status\",\"detail\":$(printf '%s' "$detail" | json_escape)}"
  case "$status" in FAIL) FAILURES=$((FAILURES+1));; UNKNOWN) UNKNOWN=$((UNKNOWN+1));; esac
}

rootfs=$(findmnt -n -o FSTYPE / 2>/dev/null || echo unknown)
arch=$(uname -m)
kernel=$(uname -r)
os_id=$( . /etc/os-release 2>/dev/null; echo "${ID:-unknown}" )
os_version=$( . /etc/os-release 2>/dev/null; echo "${VERSION_ID:-unknown}" )
provider="${VAGRANT_PROVIDER:-${PROVIDER:-unknown}}"

cgroup="$(stat -fc %T /sys/fs/cgroup 2>/dev/null || true)"
[ "$cgroup" = "cgroup2fs" ] && add cgroup_v2 PASS "cgroup2fs" || add cgroup_v2 FAIL "${cgroup:-missing}"

if [ "$(swapon --show --noheadings 2>/dev/null | wc -l)" -eq 0 ]; then add swap PASS "disabled"; else add swap FAIL "enabled"; fi

for m in overlay br_netfilter; do
  grep -q "^$m " /proc/modules 2>/dev/null && add "module_$m" PASS loaded || add "module_$m" FAIL not-loaded
done

grep -q '^iscsi_tcp ' /proc/modules 2>/dev/null && add module_iscsi_tcp PASS loaded || add module_iscsi_tcp UNKNOWN not-loaded

for p in /proc/sys/net/ipv4/ip_forward /proc/sys/net/bridge/bridge-nf-call-iptables; do
  id="sysctl_$(basename "$p" | tr '-' '_')"
  [ -r "$p" ] && [ "$(cat "$p")" = 1 ] && add "$id" PASS "1" || add "$id" FAIL "$(cat "$p" 2>/dev/null || echo missing)"
done

mountpoint -q /sys/fs/bpf 2>/dev/null && add bpffs PASS mounted || add bpffs UNKNOWN not-mounted

if systemctl cat containerd >/dev/null 2>&1; then
  grep -Rqs 'SystemdCgroup[[:space:]]*=[[:space:]]*true' /etc/containerd /etc 2>/dev/null && add containerd_systemdcgroup PASS enabled || add containerd_systemdcgroup FAIL not-enabled
else
  add containerd_systemdcgroup UNKNOWN containerd-not-installed
fi

for bin in runc ctr; do command -v "$bin" >/dev/null 2>&1 && add "runtime_$bin" PASS present || add "runtime_$bin" UNKNOWN missing; done

for dep in iscsiadm cryptsetup dmsetup; do command -v "$dep" >/dev/null 2>&1 && add "csi_$dep" PASS present || add "csi_$dep" UNKNOWN missing; done

if systemctl is-active --quiet chrony 2>/dev/null || chronyc tracking >/dev/null 2>&1; then
  chronyc tracking 2>/dev/null | grep -Eq 'Leap status[[:space:]]*:[[:space:]]*Normal' && add time_sync PASS synchronized || add time_sync UNKNOWN chrony-present-not-confirmed
else add time_sync FAIL chrony-not-active; fi

[ -d /sys/module/apparmor ] && add apparmor PASS loaded || add apparmor UNKNOWN not-loaded
[ -r /proc/self/status ] && grep -q '^Seccomp:' /proc/self/status && add seccomp PASS kernel-interface || add seccomp UNKNOWN unavailable
[ -S /run/auditd.sock ] || [ -f /run/auditd.pid ] && add auditd PASS active || add auditd UNKNOWN not-active

for f in /proc/sys/net/netfilter/nf_conntrack_max /proc/sys/net/ipv4/tcp_syncookies; do
  [ -r "$f" ] && add "network_$(basename "$f")" PASS "$(cat "$f")" || add "network_$(basename "$f")" UNKNOWN missing
done

ulimit_n=$(ulimit -n)
[ "$ulimit_n" -ge 65536 ] && add nofile PASS "$ulimit_n" || add nofile UNKNOWN "$ulimit_n"

case "$rootfs" in ext4|xfs) add filesystem PASS "$rootfs";; *) add filesystem FAIL "$rootfs";; esac

if [ -n "$EXPECTED_K8S" ]; then add kubernetes_compatibility UNKNOWN "version=$EXPECTED_K8S requires installed kubelet/runtime matrix"; else add kubernetes_compatibility UNKNOWN version-not-selected; fi
if [ -n "$EXPECTED_RUNTIME" ]; then add runtime_compatibility UNKNOWN "containerd=$EXPECTED_RUNTIME"; else add runtime_compatibility UNKNOWN version-not-selected; fi

if [ "$arch" = x86_64 ] || [ "$arch" = aarch64 ]; then add architecture PASS "$arch"; else add architecture UNKNOWN "$arch"; fi
case "$provider" in virtualbox|vmware_desktop|vmware_fusion) add provider PASS "$provider";; unknown) add provider UNKNOWN unknown;; *) add provider UNKNOWN "$provider";; esac

status=PASS
[ "$FAILURES" -gt 0 ] && status=FAIL
if [ "$STRICT" = 1 ] && [ "$UNKNOWN" -gt 0 ] && [ "$status" = PASS ]; then status=FAIL; fi

checks_json=$(IFS=,; echo "${checks[*]}")
mkdir -p "$(dirname "$OUT")"
cat > "$OUT" <<EOF
{"schema":"$SCHEMA","kind":"kubernetes-node-readiness","status":"$status","os":{"id":"$os_id","version":"$os_version"},"kernel":"$kernel","architecture":"$arch","provider":"$provider","root_filesystem":"$rootfs","kubernetes_version":"$EXPECTED_K8S","containerd_version":"$EXPECTED_RUNTIME","failures":$FAILURES,"unknowns":$UNKNOWN,"checks":[$checks_json]}
EOF

cat "$OUT"
[ "$status" = PASS ] && exit 0 || exit 1
