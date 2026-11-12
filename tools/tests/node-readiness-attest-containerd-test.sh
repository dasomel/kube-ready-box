#!/usr/bin/env bash
# The containerd readiness check must only accept evidence from /etc/containerd.
# D7: test the real script against a temporary copy with literal paths rewritten;
# production has no evidence-source override.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

mkdir -p "$WORKDIR/etc/containerd" "$WORKDIR/etc/unrelated" "$WORKDIR/bin"
cp "$ROOT/tools/node-readiness-attest.sh" "$WORKDIR/attest.sh"
sed -i.bak "s|/etc/containerd|$WORKDIR/etc/containerd|g; s|/etc/os-release|$WORKDIR/etc/os-release|g; s|/proc/modules|$WORKDIR/proc/modules|g; s|/proc/sys/|$WORKDIR/proc/sys/|g; s|/proc/self/status|$WORKDIR/proc/self/status|g; s|/sys/fs/bpf|$WORKDIR/sys/fs/bpf|g; s|/sys/module/apparmor/parameters/enabled|$WORKDIR/sys/module/apparmor/parameters/enabled|g; s|/run/auditd.sock|$WORKDIR/run/auditd.sock|g; s|/run/auditd.pid|$WORKDIR/run/auditd.pid|g" "$WORKDIR/attest.sh"
rm -f "$WORKDIR/attest.sh.bak"

cat > "$WORKDIR/etc/os-release" <<'EOF'
ID=ubuntu
VERSION_ID=24.04
EOF
printf '%s\n' 'SystemdCgroup = true' > "$WORKDIR/etc/unrelated/config.conf"
mkdir -p "$WORKDIR/proc/sys/net/ipv4" "$WORKDIR/proc/sys/net/bridge" "$WORKDIR/proc/sys/net/netfilter" "$WORKDIR/proc/self" "$WORKDIR/sys/fs/bpf" "$WORKDIR/sys/module/apparmor/parameters" "$WORKDIR/run" "$WORKDIR/bin"
printf '%s\n' 'overlay 1 0 - Live 0x0' 'br_netfilter 1 0 - Live 0x0' > "$WORKDIR/proc/modules"
printf '%s\n' 'Seccomp: 2' > "$WORKDIR/proc/self/status"
printf '1\n' > "$WORKDIR/proc/sys/net/ipv4/ip_forward"
printf '1\n' > "$WORKDIR/proc/sys/net/bridge/bridge-nf-call-iptables"
printf '1000\n' > "$WORKDIR/proc/sys/net/netfilter/nf_conntrack_max"
printf '1\n' > "$WORKDIR/proc/sys/net/ipv4/tcp_syncookies"
printf 'Y\n' > "$WORKDIR/sys/module/apparmor/parameters/enabled"

cat > "$WORKDIR/bin/findmnt" <<'SHIM'
#!/usr/bin/env bash
printf 'ext4\n'
SHIM
cat > "$WORKDIR/bin/systemctl" <<'SHIM'
#!/usr/bin/env bash
case "${1:-}" in
  cat) exit 0 ;;
  is-active) exit 1 ;;
esac
exit 1
SHIM
cat > "$WORKDIR/bin/swapon" <<'SHIM'
#!/usr/bin/env bash
exit 0
SHIM
cat > "$WORKDIR/bin/mountpoint" <<'SHIM'
#!/usr/bin/env bash
exit 0
SHIM
cat > "$WORKDIR/bin/chronyc" <<'SHIM'
#!/usr/bin/env bash
exit 1
SHIM
chmod +x "$WORKDIR/bin/"*

set +e
PATH="$WORKDIR/bin:$PATH" READINESS_OUTPUT="$WORKDIR/result.json" bash "$WORKDIR/attest.sh" >"$WORKDIR/stdout" 2>"$WORKDIR/stderr"
result=$?
set -e
python3 - "$WORKDIR/result.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
check = next(c for c in data["checks"] if c["id"] == "containerd_systemdcgroup")
if (check["status"], check["detail"]) != ("FAIL", "not-enabled"):
    raise SystemExit(f"expected containerd_systemdcgroup FAIL/not-enabled, got {check}")
PY
if [ "$result" -eq 0 ]; then
  echo "::error::unrelated /etc evidence incorrectly made readiness PASS" >&2
  exit 1
fi
echo "node-readiness-attest-containerd-test.sh: unrelated /etc evidence rejected"
