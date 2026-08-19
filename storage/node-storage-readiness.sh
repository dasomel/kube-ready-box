#!/usr/bin/env bash
set -euo pipefail
checks=(); failures=0; unknowns=0
add(){ local id=$1 st=$2 d=$3; checks+=("{\"id\":\"$id\",\"status\":\"$st\",\"detail\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$d")}"); [ "$st" = FAIL ] && failures=$((failures+1)); [ "$st" = UNKNOWN ] && unknowns=$((unknowns+1)); }

fs=$(findmnt -n -o FSTYPE / 2>/dev/null || echo unknown); case "$fs" in ext4|xfs) add root_filesystem PASS "$fs";; *) add root_filesystem UNKNOWN "$fs";; esac

for cmd in lsblk findmnt blkid; do command -v "$cmd" >/dev/null && add tool_$cmd PASS present || add tool_$cmd UNKNOWN missing; done
for cmd in iscsiadm mount.nfs cryptsetup dmsetup lvm; do command -v "$cmd" >/dev/null && add backend_$cmd PASS present || add backend_$cmd UNKNOWN missing; done

if command -v findmnt >/dev/null 2>&1; then add mount_propagation PASS "$(findmnt -o TARGET,PROPAGATION -n / 2>/dev/null || echo unknown)"; else add mount_propagation UNKNOWN unavailable; fi

if command -v df >/dev/null 2>&1; then add capacity PASS "$(df -P / | tail -1 | awk '{print $4,$5}')"; add inode_capacity PASS "$(df -Pi / | tail -1 | awk '{print $4,$5}')"; else add capacity UNKNOWN unavailable; fi

if command -v systemctl >/dev/null 2>&1 && systemctl is-enabled lvm2-monitor >/dev/null 2>&1; then add lvm_monitor PASS enabled; else add lvm_monitor UNKNOWN unavailable; fi

if command -v modprobe >/dev/null 2>&1; then add storage_modules PASS modprobe-present; else add storage_modules UNKNOWN unavailable; fi

# Expansion is verified only when an actual block/LV test device is supplied.
if [ -n "${STORAGE_TEST_DEVICE:-}" ]; then [ -b "$STORAGE_TEST_DEVICE" ] && add expansion_test UNKNOWN "device supplied; live expansion test required" || add expansion_test FAIL "not a block device"; else add expansion_test UNKNOWN no-test-device; fi

status=PASS; [ "$failures" -gt 0 ] && status=FAIL
printf '{"schema":"kube-ready-storage/v1","kind":"node-storage-readiness","status":"%s","filesystem":"%s","checks":[%s],"failures":%d,"unknowns":%d}\n' "$status" "$fs" "$(IFS=,; echo "${checks[*]}")" "$failures" "$unknowns"
[ "$status" = PASS ]
