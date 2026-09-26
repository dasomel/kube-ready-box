#!/usr/bin/env bash
set -euo pipefail
checks=(); failures=0; unknowns=0
add(){ local id=$1 st=$2 d=$3; checks+=("{\"id\":\"$id\",\"status\":\"$st\",\"detail\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$d")}"); case "$st" in FAIL) failures=$((failures+1));; UNKNOWN) unknowns=$((unknowns+1));; esac; }

fs=$(findmnt -n -o FSTYPE / 2>/dev/null || echo unknown); case "$fs" in ext4|xfs) add root_filesystem PASS "$fs";; *) add root_filesystem UNKNOWN "$fs";; esac

for cmd in lsblk findmnt blkid; do command -v "$cmd" >/dev/null && add tool_$cmd PASS present || add tool_$cmd UNKNOWN missing; done
for cmd in iscsiadm mount.nfs cryptsetup dmsetup lvm; do command -v "$cmd" >/dev/null && add backend_$cmd PASS present || add backend_$cmd UNKNOWN missing; done

if command -v findmnt >/dev/null 2>&1; then add mount_propagation PASS "$(findmnt -o TARGET,PROPAGATION -n / 2>/dev/null || echo unknown)"; else add mount_propagation UNKNOWN unavailable; fi

if command -v df >/dev/null 2>&1; then
  cap_line=$(df -P / | tail -1); cap_avail=$(printf '%s' "$cap_line" | awk '{print $4}') || true; cap_pct=$(printf '%s' "$cap_line" | awk '{print $5}' | tr -d '%') || true
  add capacity PASS "$cap_avail $cap_pct%"
  inode_line=$(df -Pi / | tail -1); inode_avail=$(printf '%s' "$inode_line" | awk '{print $4}') || true; inode_pct=$(printf '%s' "$inode_line" | awk '{print $5}' | tr -d '%') || true
  add inode_capacity PASS "$inode_avail $inode_pct%"
  if [ "${cap_pct:-0}" -gt 90 ] || [ "${inode_pct:-0}" -gt 90 ]; then add capacity_threshold FAIL "disk=${cap_pct}% inode=${inode_pct}%"; else add capacity_threshold PASS "disk=${cap_pct}% inode=${inode_pct}%"; fi
else
  add capacity UNKNOWN unavailable
  add capacity_threshold UNKNOWN unavailable
fi

if command -v systemctl >/dev/null 2>&1 && systemctl is-enabled lvm2-monitor >/dev/null 2>&1; then add lvm_monitor PASS enabled; else add lvm_monitor UNKNOWN unavailable; fi

if [ -r /proc/modules ]; then
  loaded_mods=$(awk '{print $1}' /proc/modules) || true
  relevant_mods="nfs nfsv4 iscsi_tcp dm_mod overlay"
  found_mods=""
  for m in $relevant_mods; do if grep -qx "$m" <<<"$loaded_mods"; then found_mods="$found_mods $m"; fi; done
  found_mods=$(echo "$found_mods" | xargs) || true
  if [ -n "$found_mods" ]; then add storage_modules PASS "loaded:$found_mods (checked:$relevant_mods)"; else add storage_modules UNKNOWN "none of ($relevant_mods) loaded; may be built-in"; fi
else
  add storage_modules UNKNOWN /proc/modules-unavailable
fi

os_id=$( { grep -m1 '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"'; } || true); [ -n "$os_id" ] && add os_id PASS "$os_id" || add os_id UNKNOWN unavailable
os_id_like=$( { grep -m1 '^ID_LIKE=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"'; } || true)

# mac_backend routes to the native LSM by OS family (ID, then ID_LIKE) --
# never by which tool (getenforce/aa-status) happens to be on PATH, which
# misreports an AppArmor-native host with a stray getenforce binary as
# SELinux, and vice versa. This mirrors classify_lsm_family in
# security/workload-security-check.sh exactly (PR 1b, f2b61f2) so the two
# validators cannot disagree on which LSM a host is native to. It must not
# PASS for a disabled/permissive native LSM (#44 C-06/T-021, D4): SELinux
# Permissive/Disabled is FAIL, and AppArmor is read from the kernel module
# parameter (not aa-status, and not bare /sys/module/apparmor existence) so
# a loaded-but-disabled module is FAIL rather than the previous false PASS.
# An unreadable/absent AppArmor parameter is UNKNOWN, never a PASS/FAIL
# guess from aa-status's mere presence.
classify_storage_lsm_family() {
  case "$1" in
    ubuntu|debian|nixos) printf '%s' apparmor; return ;;
    rocky|rhel|alma|almalinux|fedora|centos) printf '%s' selinux; return ;;
  esac
  for os_like in $2; do
    case "$os_like" in
      ubuntu|debian|nixos) printf '%s' apparmor; return ;;
      rocky|rhel|alma|almalinux|fedora|centos) printf '%s' selinux; return ;;
    esac
  done
  printf '%s' unknown
}

mac_lsm_family=$(classify_storage_lsm_family "$os_id" "$os_id_like")
case "$mac_lsm_family" in
  selinux)
    sel_state=$(getenforce 2>/dev/null || echo unavailable)
    case "$sel_state" in
      Enforcing) add mac_backend PASS "selinux:$sel_state" ;;
      Permissive|Disabled) add mac_backend FAIL "selinux:$sel_state" ;;
      *) add mac_backend UNKNOWN "selinux:$sel_state" ;;
    esac
    ;;
  apparmor)
    if aa_state=$(cat /sys/module/apparmor/parameters/enabled 2>/dev/null); then
      case "$aa_state" in
        Y) add mac_backend PASS "apparmor:enabled" ;;
        N) add mac_backend FAIL "apparmor:disabled" ;;
        *) add mac_backend UNKNOWN "apparmor:unexpected-value:$aa_state" ;;
      esac
    else
      add mac_backend UNKNOWN "apparmor:parameters-unreadable"
    fi
    ;;
  *)
    add mac_backend UNKNOWN "$os_id"
    ;;
esac

qopts=$(findmnt -no OPTIONS / 2>/dev/null || mount 2>/dev/null | awk '$3=="/"{print $0}') || true
case "$qopts" in
  *prjquota*|*pquota*|*usrquota*) add quota_capability PASS "mount-option:$qopts" ;;
  *)
    if command -v xfs_quota >/dev/null 2>&1; then add quota_capability PASS xfs_quota-present
    elif command -v repquota >/dev/null 2>&1; then add quota_capability PASS repquota-present
    else add quota_capability UNKNOWN no-quota-mechanism-detected
    fi
    ;;
esac

# Expansion is verified only when an actual block/LV test device is supplied.
if [ -n "${STORAGE_TEST_DEVICE:-}" ]; then [ -b "$STORAGE_TEST_DEVICE" ] && add expansion_test UNKNOWN "device supplied; live expansion test required" || add expansion_test FAIL "not a block device"; else add expansion_test UNKNOWN no-test-device; fi

status=PASS; [ "$failures" -gt 0 ] && status=FAIL
printf '{"schema":"kube-ready-storage/v1","kind":"node-storage-readiness","status":"%s","filesystem":"%s","checks":[%s],"failures":%d,"unknowns":%d}\n' "$status" "$fs" "$(IFS=,; echo "${checks[*]}")" "$failures" "$unknowns"
[ "$status" = PASS ]
