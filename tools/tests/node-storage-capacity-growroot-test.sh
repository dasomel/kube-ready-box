#!/usr/bin/env bash
# Deterministic fixtures for storage/node-storage-readiness.sh (#18):
# capacity_threshold (>90% disk/inode FAIL, non-numeric UNKNOWN) and
# growroot_evidence (kube-ready-growroot/v1: missing/UNKNOWN/garbage ->
# UNKNOWN, FAIL -> FAIL, PASS -> PASS). Runs a temp copy of the real script
# with only the growroot path redirected; `df` is shimmed on PATH (no
# production env bypass). Must pass on macOS and Linux.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

sed -e "s|/etc/vagrant-box/growroot.json|$WORKDIR/growroot.json|g" \
  "$ROOT/storage/node-storage-readiness.sh" > "$WORKDIR/node-storage-readiness.sh"

bindir="$WORKDIR/bin"; mkdir -p "$bindir"
for tool in bash python3 grep cut tr awk printf tail head cat; do
  real=$(command -v "$tool" 2>/dev/null || true)
  [ -n "$real" ] && ln -sf "$real" "$bindir/$tool"
done
# df shim: DF_PCT / DF_IPCT drive the Use% column for `df -P` / `df -Pi`.
cat > "$bindir/df" <<'SHIM'
#!/usr/bin/env bash
if [ "${1:-}" = "-Pi" ]; then pct=$DF_IPCT; else pct=$DF_PCT; fi
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
echo "/dev/x 1000 100 900 ${pct} /"
SHIM
chmod +x "$bindir/df"

fail=0
check() { # name expected_status check_id
  local out st
  out=$(PATH="$bindir" bash "$WORKDIR/node-storage-readiness.sh" 2>/dev/null || true)
  st=$(printf '%s' "$out" | python3 -c 'import json,sys
d=json.load(sys.stdin)
print(next(c["status"] for c in d["checks"] if c["id"]==sys.argv[1]))' "$3") || st=ERROR
  if [ "$st" = "$2" ]; then echo "ok   $1 ($3=$st)"; else echo "FAIL $1: $3 want $2 got $st"; fail=1; fi
}

export DF_PCT=50% DF_IPCT=50%
check "disk 50%" PASS capacity_threshold
DF_PCT=90% check "disk 90% boundary" PASS capacity_threshold
DF_PCT=91% check "disk 91%" FAIL capacity_threshold
DF_IPCT=95% check "inode 95%" FAIL capacity_threshold
DF_IPCT=- check "inode non-numeric" UNKNOWN capacity_threshold

rm -f "$WORKDIR/growroot.json"
check "growroot missing" UNKNOWN growroot_evidence
w() { printf '%s\n' "$1" > "$WORKDIR/growroot.json"; }
w '{"schema":"kube-ready-growroot/v1","status":"PASS","filesystem":"ext4","lv_bytes":1}'; check "growroot PASS" PASS growroot_evidence
w '{"schema":"kube-ready-growroot/v1","status":"FAIL"}'; check "growroot FAIL" FAIL growroot_evidence
w '{"schema":"kube-ready-growroot/v1","status":"UNKNOWN"}'; check "growroot UNKNOWN" UNKNOWN growroot_evidence
w '{"schema":"other/v1","status":"PASS"}'; check "growroot wrong schema" UNKNOWN growroot_evidence
w 'not json'; check "growroot garbage" UNKNOWN growroot_evidence

exit "$fail"
