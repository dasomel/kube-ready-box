#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/config"
cp "$ROOT/packer/plugins.pkr.hcl" "$work/config/"
export CALLS="$work/calls" COUNT="$work/count"
cat > "$work/bin/uname" <<'SH'
#!/usr/bin/env bash
case "$1" in -s) echo Linux;; -m) echo x86_64;; esac
SH
cat > "$work/bin/packer" <<'SH'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$CALLS"
if [ "$1" = plugins ]; then exit 0; fi
n=0
[ ! -f "$COUNT" ] || n=$(cat "$COUNT")
n=$((n+1)); echo "$n" > "$COUNT"
[ "$MODE" = normal ] || { [ "$n" -gt 1 ] && [ "$MODE" != retry-fails ]; }
SH
cat > "$work/bin/gh" <<'SH'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$CALLS"
while [ "$#" -gt 0 ]; do
  if [ "$1" = --dir ]; then shift; stage=$1; fi
  shift
done
name=packer-plugin-vmware_v2.1.4_x5.0_linux_amd64.zip
printf 'fixture\n' > "$stage/$name"
if [ "$MODE" != missing-checksum ]; then
  hash=$(sha256sum "$stage/$name" | cut -d' ' -f1)
  if [ "$MODE" = corrupt ]; then hash=$(printf '%064d' 0); fi
  printf '%s  %s\n' "$hash" "$name" > "$stage/packer-plugin-vmware_v2.1.4_SHA256SUMS"
else
  printf 'no matching archive\n' > "$stage/packer-plugin-vmware_v2.1.4_SHA256SUMS"
fi
SH
cat > "$work/bin/unzip" <<'SH'
#!/usr/bin/env bash
printf 'unzip\n' >> "$CALLS"
SH
chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH"
run_case() {
  export MODE=$1
  : > "$CALLS"; rm -f "$COUNT"
  if (cd "$work/config" && bash "$ROOT/tools/packer-init.sh") > "$work/output" 2>&1; then rc=0; else rc=$?; fi
  if [ "$2" = pass ]; then [ "$rc" -eq 0 ]; else [ "$rc" -ne 0 ]; fi
  case "$MODE" in
    normal) ! grep -q 'release download' "$CALLS";;
    corrupt|missing-checksum) ! grep -q '^unzip\|^plugins install' "$CALLS";;
    fallback|retry-fails)
      grep -q '^plugins install --path ./packer-plugin-vmware_v2.1.4_x5.0_linux_amd64 github.com/vmware/vmware$' "$CALLS"
      [ "$(cat "$COUNT")" -eq 2 ];;
  esac
  echo "PASS $MODE"
}
run_case normal pass
run_case fallback pass
run_case corrupt fail
run_case missing-checksum fail
run_case retry-fails fail
