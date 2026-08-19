#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 dasomel
set -euo pipefail

echo "========================================"
echo "=== K8s Node Tuning Verification ==="
echo "========================================"
echo -e "\n[1] 스왑 상태"
free -h | grep Swap

echo -e "\n[2] 커널 파라미터"
echo "  net.ipv4.ip_forward: $(sysctl -n net.ipv4.ip_forward)"
echo "  vm.swappiness: $(sysctl -n vm.swappiness)"
echo "  fs.file-max: $(sysctl -n fs.file-max)"
echo "  net.core.somaxconn: $(sysctl -n net.core.somaxconn)"
echo "  kernel.pid_max: $(sysctl -n kernel.pid_max)"
echo "  fs.inotify.max_user_watches: $(sysctl -n fs.inotify.max_user_watches)"

echo -e "\n[3] 리소스 제한"
echo "  File descriptors (nofile): $(ulimit -n)"
echo "  Max processes (nproc): $(ulimit -u)"

echo -e "\n[4] 커널 모듈"
lsmod | grep -E "overlay|br_netfilter" || echo "  WARNING: overlay or br_netfilter not loaded"

echo -e "\n[5] Cgroup 버전"
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
  echo "  cgroup v2 detected"
  cat /sys/fs/cgroup/cgroup.controllers
else
  echo "  cgroup v1 detected"
fi

echo -e "\n[6] 컨테이너 런타임 상태 (K8s 설치 후)"
systemctl is-active containerd 2>/dev/null || echo "  미설치 (정상 - 사용자가 설치)"

echo -e "\n[7] kubelet 상태 (K8s 설치 후)"
systemctl is-active kubelet 2>/dev/null || echo "  미설치 (정상 - 사용자가 설치)"

echo -e "\n[8] 네트워크 인터페이스"
ip link show | grep -E "^[0-9]+:" | awk '{print "  "$2}'

echo -e "\n[9] 디스크 정보"
df -h / | tail -n1

echo -e "\n[10] 디스크 튜닝 상태"
echo "  I/O Scheduler:"
for sched in /sys/block/sd*/queue/scheduler /sys/block/nvme*/queue/scheduler; do
  if [ -f "$sched" ]; then
    disk_name=$(echo "$sched" | cut -d'/' -f4)
    current=$(grep -oP '\[\K[^\]]+' "$sched" || cat "$sched")
    echo "    $disk_name: $current"
  fi
done 2>/dev/null || echo "    (no block devices found)"

echo "  Read-ahead:"
for ra in /sys/block/sd*/queue/read_ahead_kb /sys/block/nvme*/queue/read_ahead_kb; do
  if [ -f "$ra" ]; then
    disk_name=$(echo "$ra" | cut -d'/' -f4)
    value=$(cat "$ra")
    echo "    $disk_name: ${value}KB"
  fi
done 2>/dev/null || echo "    (no block devices found)"

echo "  Mount options (noatime):"
if grep -q "noatime" /etc/fstab; then
  echo "    fstab: configured"
else
  echo "    fstab: not configured"
fi
if mount | grep -q "noatime"; then
  echo "    current: enabled"
else
  echo "    current: not enabled"
fi

echo "  LVM auto-extend service:"
if systemctl is-enabled extend-lvm.service >/dev/null 2>&1; then
  echo "    enabled: yes"
else
  echo "    enabled: no"
fi

echo -e "\n========================================"
echo "=== K8s Ready OS Check Complete ==="
echo "========================================"
echo ""
echo "This OS is ready for Kubernetes installation."
echo "Next steps (user action required):"
echo "  1. Install container runtime (containerd or CRI-O)"
echo "  2. Install kubeadm, kubelet, kubectl"
echo "  3. Initialize cluster or join existing cluster"
echo ""

# Machine-readable Kubernetes node preflight validator.
# Runtime packages remain optional in the base image; set STRICT_RUNTIME=1
# when a test environment requires containerd/SystemdCgroup to be installed.
echo -e "\n[11] Installing Kubernetes node preflight validator"
cat > /usr/local/bin/k8s-node-preflight <<'PREFLIGHT'
#!/usr/bin/env bash
set -u

FORMAT="${1:-text}"
STRICT_RUNTIME="${STRICT_RUNTIME:-0}"
failures=0
unknowns=0
checks=()

record() {
  local id="$1" status="$2" detail="$3"
  checks+=("$id"$'\t'"$status"$'\t'"$detail")
  case "$status" in
    FAIL) failures=$((failures + 1)) ;;
    UNKNOWN|SKIP) unknowns=$((unknowns + 1)) ;;
  esac
}

. /etc/os-release
record os_id PASS "${ID:-unknown}"
record os_version PASS "${VERSION_ID:-unknown}"
record architecture PASS "$(uname -m)"

if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
  record cgroup_v2 PASS "cgroup.controllers present"
else
  record cgroup_v2 FAIL "cgroup v2 not detected"
fi

if [ -z "$(swapon --show 2>/dev/null)" ]; then
  record swap_disabled PASS "no active swap"
else
  record swap_disabled FAIL "active swap detected"
fi

for item in \
  "net.ipv4.ip_forward=1" \
  "net.bridge.bridge-nf-call-iptables=1" \
  "net.bridge.bridge-nf-call-ip6tables=1"
do
  key="${item%%=*}"
  expected="${item#*=}"
  actual="$(sysctl -n "$key" 2>/dev/null || true)"
  if [ "$actual" = "$expected" ]; then
    record "sysctl_${key//./_}" PASS "$actual"
  else
    record "sysctl_${key//./_}" FAIL "expected=${expected},actual=${actual:-unset}"
  fi
done

for mod in overlay br_netfilter iscsi_tcp; do
  if lsmod | awk '{print $1}' | grep -qx "$mod"; then
    record "module_${mod}" PASS "loaded"
  elif modprobe -n "$mod" >/dev/null 2>&1; then
    record "module_${mod}" FAIL "available but not loaded"
  else
    record "module_${mod}" FAIL "module unavailable"
  fi
done

if mountpoint -q /sys/fs/bpf 2>/dev/null && [ "$(stat -f -c %T /sys/fs/bpf 2>/dev/null)" = "bpf" ]; then
  record bpffs PASS "mounted"
else
  record bpffs FAIL "bpffs not mounted"
fi

for cmd in open-iscsi cryptsetup dmsetup; do
  if command -v "$cmd" >/dev/null 2>&1 || dpkg-query -W -f='${Status}' "$cmd" 2>/dev/null | grep -q 'install ok installed'; then
    record "pkg_${cmd//-/_}" PASS "installed"
  else
    record "pkg_${cmd//-/_}" FAIL "missing"
  fi
done

if command -v chronyc >/dev/null 2>&1; then
  if chronyc tracking >/dev/null 2>&1 && chronyc waitsync 1 0.5 >/dev/null 2>&1; then
    offset="$(chronyc tracking 2>/dev/null | awk -F: '/Last offset/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')"
    record time_sync PASS "${offset:-synchronized}"
  else
    record time_sync FAIL "chrony is not synchronized"
  fi
else
  record time_sync FAIL "chrony not installed"
fi

if command -v aa-status >/dev/null 2>&1; then
  if aa-status --enabled >/dev/null 2>&1; then
    record apparmor PASS "enabled"
  else
    record apparmor UNKNOWN "AppArmor unavailable or disabled"
  fi
else
  record apparmor UNKNOWN "aa-status unavailable"
fi

if command -v auditctl >/dev/null 2>&1; then
  if systemctl is-active --quiet auditd 2>/dev/null; then
    record auditd PASS "active"
  else
    record auditd UNKNOWN "installed but inactive"
  fi
else
  record auditd FAIL "auditd not installed"
fi

root_source="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
root_fstype="$(findmnt -n -o FSTYPE / 2>/dev/null || true)"
if [ "$root_fstype" = "ext4" ] || [ "$root_fstype" = "xfs" ]; then
  record filesystem PASS "${root_source}:${root_fstype}"
else
  record filesystem FAIL "unsupported root filesystem: ${root_fstype:-unknown}"
fi

if systemctl is-enabled --quiet extend-lvm.service 2>/dev/null; then
  record lvm_auto_extend PASS "enabled"
else
  record lvm_auto_extend UNKNOWN "extend-lvm.service not enabled"
fi

if command -v containerd >/dev/null 2>&1; then
  if systemctl is-active --quiet containerd 2>/dev/null; then
    if containerd config dump 2>/dev/null | grep -Eq 'SystemdCgroup[[:space:]]*=[[:space:]]*true|systemd_cgroup[[:space:]]*=[[:space:]]*true'; then
      record containerd_systemd_cgroup PASS "enabled"
    else
      record containerd_systemd_cgroup FAIL "SystemdCgroup not enabled"
    fi
  else
    record containerd_systemd_cgroup FAIL "containerd installed but inactive"
  fi
else
  if [ "$STRICT_RUNTIME" = "1" ]; then
    record containerd_systemd_cgroup FAIL "containerd not installed"
  else
    record containerd_systemd_cgroup UNKNOWN "containerd not installed in base box"
  fi
fi

if [ "$(ulimit -n)" -ge 65536 ]; then
  record nofile_limit PASS "$(ulimit -n)"
else
  record nofile_limit FAIL "$(ulimit -n)"
fi

status="PASS"
[ "$failures" -gt 0 ] && status="FAIL"
if [ "$FORMAT" = "json" ]; then
  printf '{\n'
  printf '  "schema_version": "1.0",\n'
  printf '  "status": "%s",\n' "$status"
  printf '  "failures": %d,\n' "$failures"
  printf '  "unknowns": %d,\n' "$unknowns"
  printf '  "checks": [\n'
  last=$(( ${#checks[@]} - 1 ))
  for i in "${!checks[@]}"; do
    IFS=$'\t' read -r id check_status detail <<< "${checks[$i]}"
    detail=${detail//\\/\\\\}
    detail=${detail//\"/\\\"}
    printf '    {"id":"%s","status":"%s","detail":"%s"}' "$id" "$check_status" "$detail"
    [ "$i" -lt "$last" ] && printf ','
    printf '\n'
  done
  printf '  ]\n}\n'
else
  printf 'Kubernetes Node Preflight\n'
  printf 'schema_version=1.0 status=%s failures=%d unknowns=%d\n\n' "$status" "$failures" "$unknowns"
  for entry in "${checks[@]}"; do
    IFS=$'\t' read -r id check_status detail <<< "$entry"
    printf '%-32s %-7s %s\n' "$id" "$check_status" "$detail"
  done
fi

[ "$failures" -eq 0 ]
PREFLIGHT
chmod 0755 /usr/local/bin/k8s-node-preflight
echo "  Installed: /usr/local/bin/k8s-node-preflight"
