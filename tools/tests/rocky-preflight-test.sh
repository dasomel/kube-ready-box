#!/usr/bin/env bash
# Deterministic fixture coverage for #15: rocky/preflight.sh had no unit tests.
# Runs a temporary copy of the real script whose literal /etc, /proc and /sys
# paths are rewritten by sed to a per-case fixture tree (D7: no production
# env-var override for evidence sources), with every external command resolved
# from a hermetic PATH of shims -- so host tools (getenforce, systemctl,
# swapon, findmnt, mountpoint, stat, ...) never leak in and results are the
# same on macOS (BSD tools, bash 3.2) and Linux CI. A command with no shim is
# "not installed" for the script.
# Contract asserted: UNKNOWN is never PASS and is counted in `unknowns`; the
# script's only stdout is one JSON line with integer failures/unknowns.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/rocky/preflight.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

REAL_BASH=$(command -v bash)

# A passthrough shim execs the real binary resolved now, so the script under
# test only ever sees tools we chose to expose.
pass_shim() {
  local bin=$1 name=$2 real
  real=$(command -v "$name")
  printf '#!/bin/bash\nexec "%s" "$@"\n' "$real" > "$bin/$name"
  chmod +x "$bin/$name"
}

# mk_shim <bin> <name> <body...>: body is literal shell run by the shim.
mk_shim() {
  local bin=$1 name=$2
  shift 2
  { printf '#!/bin/bash\n'; printf '%s\n' "$@"; } > "$bin/$name"
  chmod +x "$bin/$name"
}

# build_good <case>: an all-good Rocky 9 guest. Sets FIX and BIN.
build_good() {
  CASE_DIR="$WORKDIR/$1"
  FIX="$CASE_DIR/fix"
  BIN="$CASE_DIR/bin"
  mkdir -p "$FIX/etc/selinux" "$FIX/etc/containerd" "$FIX/proc/sys/net/ipv4" \
    "$FIX/proc/sys/net/bridge" "$FIX/sys/fs/bpf" "$BIN"

  cat > "$FIX/etc/os-release" <<'EOF'
NAME="Rocky Linux"
ID="rocky"
VERSION_ID="9.4"
PRETTY_NAME="Rocky Linux 9.4 (Blue Onyx)"
EOF
  echo 'SELINUX=enforcing' > "$FIX/etc/selinux/config"
  echo 'SystemdCgroup = true' > "$FIX/etc/containerd/config.toml"
  printf '%s\n' 'overlay 200000 0 - Live 0x0' 'br_netfilter 32768 0 - Live 0x0' \
    'nf_conntrack 180000 1 br_netfilter, Live 0x0' 'dm_mod 180000 0 - Live 0x0' > "$FIX/proc/modules"
  echo 1 > "$FIX/proc/sys/net/ipv4/ip_forward"
  echo 1 > "$FIX/proc/sys/net/bridge/bridge-nf-call-iptables"
  echo Enforcing > "$FIX/getenforce"
  echo cgroup2fs > "$FIX/cgroup_fstype"
  : > "$FIX/swapon"
  echo xfs > "$FIX/root_fstype"
  : > "$FIX/bpffs_mounted"
  echo 'Value: /usr/sbin/iptables-nft' > "$FIX/iptables_query"
  echo x86_64 > "$FIX/machine"
  : > "$FIX/active_NetworkManager"
  : > "$FIX/active_iscsid"
  : > "$FIX/unit_containerd"
  printf 'flags\t\t: fpu sse2 avx avx2 bmi1 bmi2 f16c\n' > "$FIX/proc/cpuinfo"

  for t in python3 grep cut awk cat basename; do pass_shim "$BIN" "$t"; done
  for t in firewall-cmd iptables chronyc iscsiadm cryptsetup dmsetup; do
    mk_shim "$BIN" "$t" 'exit 0'
  done
  mk_shim "$BIN" uname "cat '$FIX/machine'"
  mk_shim "$BIN" getenforce "[ -f '$FIX/getenforce' ] || exit 1" "cat '$FIX/getenforce'"
  mk_shim "$BIN" swapon "cat '$FIX/swapon'"
  mk_shim "$BIN" findmnt "cat '$FIX/root_fstype'"
  # The sed rewrite turns /sys/fs/cgroup / /sys/fs/bpf into fixture paths; the
  # shims answer from fixture state files instead of the host's filesystems.
  mk_shim "$BIN" stat "[ -f '$FIX/cgroup_fstype' ] || exit 1" "cat '$FIX/cgroup_fstype'"
  mk_shim "$BIN" mountpoint "[ -f '$FIX/bpffs_mounted' ]"
  # iptables fallback when `update-alternatives --query` yields nothing.
  mk_shim "$BIN" readlink "[ -f '$FIX/readlink_out' ] || exit 1" "cat '$FIX/readlink_out'"
  mk_shim "$BIN" update-alternatives "[ -f '$FIX/iptables_query' ] || exit 1" "cat '$FIX/iptables_query'"
  mk_shim "$BIN" systemctl \
    'case "$1 $2 $3" in' \
    "  'is-active --quiet NetworkManager') [ -f '$FIX/active_NetworkManager' ];;" \
    "  'is-active --quiet iscsid') [ -f '$FIX/active_iscsid' ];;" \
    "  'cat containerd '*) [ -f '$FIX/unit_containerd' ];;" \
    "  *) exit 1;;" \
    'esac'
}

# run_case <case> -> prints "<rc> <stdout-file>"; script copy has literal paths rewritten.
run_case() {
  local name=$1 copy="$CASE_DIR/preflight.sh" out="$CASE_DIR/stdout" rc
  # One -E pass so "/proc/sys/..." is not rewritten a second time by the /sys rule.
  sed -E "s#(^|[^A-Za-z0-9_./-])/(etc|proc|sys)/#\\1$FIX/\\2/#g" "$SCRIPT" > "$copy"
  # Guard the rewrite itself: no literal evidence path may survive in code lines.
  if sed -E "s#$FIX/(etc|proc|sys)/#X/#g" "$copy" | grep -vE '^[[:space:]]*#' | grep -qE '(^|[^A-Za-z0-9_./-])/(etc|proc|sys)/'; then
    echo "::error::$name: unrewritten evidence path in script copy" >&2
    exit 1
  fi
  set +e
  env -i PATH="$BIN" "$REAL_BASH" "$copy" > "$out" 2> "$CASE_DIR/stderr"
  rc=$?
  set -e
  echo "$rc $out"
}

# assert_run <rc> <out> <expected-rc> <failures> <unknowns> [id=STATUS[:detail]]...
assert_run() {
  local rc=$1 out=$2 want_rc=$3
  shift 3
  python3 - "$rc" "$out" "$want_rc" "$@" <<'PY'
import json, sys
rc, path, want_rc, failures, unknowns, *specs = sys.argv[1:]
def die(msg):
    print(f"::error::{path}: {msg}")
    raise SystemExit(1)
raw = open(path, encoding="utf-8").read()
lines = raw.splitlines()
if len(lines) != 1:
    die(f"expected exactly one stdout line, got {len(lines)}")
try:
    doc = json.loads(lines[0])
except ValueError as e:
    die(f"final line is not valid JSON: {e}")
if rc != want_rc:
    die(f"exit code {rc}, expected {want_rc}")
for k in ("failures", "unknowns"):
    v = doc.get(k)
    if type(v) is not int:
        die(f"{k} is not an integer: {v!r}")
checks = doc["checks"]
# Counters must agree with the per-check records (nothing swallowed).
n_fail = sum(1 for c in checks if c["status"] == "FAIL")
n_unk = sum(1 for c in checks if c["status"] == "UNKNOWN")
if (doc["failures"], doc["unknowns"]) != (n_fail, n_unk):
    die(f"counters {doc['failures']}/{doc['unknowns']} disagree with checks {n_fail}/{n_unk}")
if (doc["failures"], doc["unknowns"]) != (int(failures), int(unknowns)):
    die(f"failures/unknowns {doc['failures']}/{doc['unknowns']}, expected {failures}/{unknowns}")
want_status = "FAIL" if doc["failures"] else "PASS"
if doc["status"] != want_status:
    die(f"status {doc['status']!r}, expected {want_status!r}")
if doc["schema"] != "kube-ready-readiness/v1":
    die(f"unexpected schema {doc['schema']!r}")
by_id = {c["id"]: c for c in checks}
for spec in specs:
    cid, _, rest = spec.partition("=")
    status, _, detail = rest.partition(":")
    c = by_id.get(cid)
    if c is None:
        die(f"missing check {cid!r}")
    if c["status"] != status:
        die(f"{cid}: status {c['status']!r}, expected {status!r} (detail {c['detail']!r})")
    if ":" in rest and c["detail"] != detail:
        die(f"{cid}: detail {c['detail']!r}, expected {detail!r}")
PY
}

# check <case-name> <expected-rc> <failures> <unknowns> [spec...]; FIX/BIN already built.
check() {
  local name=$1 want_rc=$2 res rc out
  shift 2
  res=$(run_case "$name")
  rc=${res%% *}
  out=${res#* }
  assert_run "$rc" "$out" "$want_rc" "$@"
  echo "ok - $name"
}

# --- allow: all-good Rocky 9 -> failures=0, only the Rocky-10-only check is UNKNOWN ---
build_good good
check good 0 0 1 \
  os=PASS:"Rocky Linux 9.4 (Blue Onyx)" architecture=PASS:x86_64 selinux=PASS:Enforcing \
  selinux_config_consistency=PASS firewalld=PASS iptables_backend=PASS:nft \
  networkmanager=PASS cgroup_v2=PASS swap=PASS:disabled module_overlay=PASS \
  module_br_netfilter=PASS module_conntrack=PASS module_dm_mod=PASS \
  sysctl_ip_forward=PASS sysctl_bridge-nf-call-iptables=PASS bpffs=PASS \
  containerd_systemdcgroup=PASS chrony=PASS csi_iscsiadm=PASS csi_cryptsetup=PASS \
  csi_dmsetup=PASS iscsid_active=PASS filesystem=PASS:xfs \
  rocky10_x86_64_v3=UNKNOWN:"not Rocky 10"

# --- deny: SELinux Disabled -> selinux FAIL (config=enforcing => drift FAIL too) ---
build_good selinux-disabled
echo Disabled > "$FIX/getenforce"
check selinux-disabled 1 2 1 selinux=FAIL:Disabled selinux_config_consistency=FAIL

# --- deny: runtime Permissive with config=permissive -> selinux FAIL, config consistent ---
build_good selinux-permissive
echo Permissive > "$FIX/getenforce"
echo 'SELINUX=permissive' > "$FIX/etc/selinux/config"
check selinux-permissive 1 1 1 selinux=FAIL:Permissive selinux_config_consistency=PASS

# --- deny: runtime Enforcing but config would not persist it -> consistency FAIL only ---
build_good selinux-config-drift
echo 'SELINUX=disabled' > "$FIX/etc/selinux/config"
check selinux-config-drift 1 1 1 selinux=PASS:Enforcing selinux_config_consistency=FAIL

# --- SELinux config value unrecognised -> consistency UNKNOWN, never PASS ---
build_good selinux-config-garbage
echo 'SELINUX=bogus' > "$FIX/etc/selinux/config"
check selinux-config-garbage 0 0 2 selinux_config_consistency=UNKNOWN:"config=bogus runtime=Enforcing"

# --- deny: swap on, modules missing/prefix-only, cgroup v1, sysctl zero/missing, containerd
# SystemdCgroup=false -> every one FAIL (none PASS). "overlayfs"/"dm_mod_extra" must not
# satisfy the "^overlay "/"^dm_mod " matches; br_netfilter is absent entirely. ---
build_good multi-fail
echo '/swapfile  file  2G  0B  -2' > "$FIX/swapon"
printf '%s\n' 'overlayfs 1 0 - Live 0x0' 'nf_conntrack 1 0 - Live 0x0' 'dm_mod_extra 1 0 - Live 0x0' \
  > "$FIX/proc/modules"
echo tmpfs > "$FIX/cgroup_fstype"
echo 0 > "$FIX/proc/sys/net/ipv4/ip_forward"
rm "$FIX/proc/sys/net/bridge/bridge-nf-call-iptables"
echo 'SystemdCgroup = false' > "$FIX/etc/containerd/config.toml"
check multi-fail 1 8 1 swap=FAIL:enabled module_overlay=FAIL:not-loaded \
  module_br_netfilter=FAIL:not-loaded module_conntrack=PASS module_dm_mod=FAIL:not-loaded \
  cgroup_v2=FAIL:missing sysctl_ip_forward=FAIL:missing-or-zero \
  sysctl_bridge-nf-call-iptables=FAIL:missing-or-zero containerd_systemdcgroup=FAIL:disabled

# --- unreadable /proc/modules: nothing proves a module is loaded -> FAIL, never PASS ---
build_good modules-unreadable
rm "$FIX/proc/modules"
check modules-unreadable 1 4 1 module_overlay=FAIL module_br_netfilter=FAIL \
  module_conntrack=FAIL module_dm_mod=FAIL

# --- unreadable / missing inputs -> UNKNOWN counted, never PASS; run stays rc 0 (no FAIL) ---
build_good unknown-inputs
rm "$FIX/getenforce" "$FIX/etc/selinux/config" "$FIX/active_NetworkManager" \
  "$FIX/active_iscsid" "$FIX/bpffs_mounted" "$FIX/unit_containerd"
rm "$BIN/firewall-cmd" "$BIN/chronyc" "$BIN/iscsiadm" "$BIN/cryptsetup" "$BIN/dmsetup" "$BIN/iptables"
echo btrfs > "$FIX/root_fstype"
check unknown-inputs 0 0 14 \
  selinux=UNKNOWN:unavailable selinux_config_consistency=UNKNOWN:"config file missing" \
  firewalld=UNKNOWN iptables_backend=UNKNOWN:"iptables not installed" networkmanager=UNKNOWN \
  bpffs=UNKNOWN containerd_systemdcgroup=UNKNOWN:not-installed chrony=UNKNOWN \
  csi_iscsiadm=UNKNOWN csi_cryptsetup=UNKNOWN csi_dmsetup=UNKNOWN iscsid_active=UNKNOWN \
  filesystem=UNKNOWN:btrfs

# --- iptables backend: legacy / nft-via-readlink / indeterminate ---
build_good iptables-legacy
echo 'Value: /usr/sbin/iptables-legacy' > "$FIX/iptables_query"
check iptables-legacy 0 0 1 iptables_backend=PASS:legacy

build_good iptables-readlink-nft
rm "$FIX/iptables_query"
echo /usr/sbin/xtables-nft-multi > "$FIX/readlink_out"
check iptables-readlink-nft 0 0 1 iptables_backend=PASS:nft

build_good iptables-indeterminate
rm "$FIX/iptables_query"
echo /usr/sbin/iptables > "$FIX/readlink_out"
check iptables-indeterminate 0 0 2 iptables_backend=UNKNOWN:/usr/sbin/iptables

# --- not Rocky / unreadable os-release -> os FAIL, never PASS ---
build_good os-not-rocky
sed -e 's/^ID=.*/ID="ubuntu"/' "$FIX/etc/os-release" > "$FIX/etc/os-release.new"
mv "$FIX/etc/os-release.new" "$FIX/etc/os-release"
check os-not-rocky 1 1 1 os=FAIL:"not Rocky Linux"

build_good os-release-missing
rm "$FIX/etc/os-release"
check os-release-missing 1 1 1 os=FAIL:"not Rocky Linux"

# --- Rocky 10 x86_64-v3 policy ---
rocky10() { sed -e 's/^VERSION_ID=.*/VERSION_ID="10.0"/' "$FIX/etc/os-release" > "$FIX/etc/os-release.new"; mv "$FIX/etc/os-release.new" "$FIX/etc/os-release"; }

build_good rocky10-v3-ok
rocky10
check rocky10-v3-ok 0 0 0 rocky10_x86_64_v3=PASS:cpu-flags

build_good rocky10-v3-missing-flag
rocky10
printf 'flags\t\t: fpu sse2 avx avx2 bmi1 f16c\n' > "$FIX/proc/cpuinfo"
check rocky10-v3-missing-flag 1 1 0 rocky10_x86_64_v3=FAIL:"missing bmi2"

build_good rocky10-non-x86
rocky10
echo aarch64 > "$FIX/machine"
check rocky10-non-x86 0 0 1 architecture=PASS:aarch64 rocky10_x86_64_v3=UNKNOWN:"non-x86_64 architecture"

echo "rocky-preflight-test.sh: all scenarios passed"
