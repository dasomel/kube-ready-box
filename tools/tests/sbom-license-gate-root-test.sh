#!/usr/bin/env bash
# Regression for #10/#28: with ROOT=<extracted image>, the license gate must hash
# the image's usr/share/doc/<pkg>/copyright, never the host's. Needs dpkg-query
# (Linux); skipped with a non-zero exit if it is unavailable so it is never
# mistaken for a pass.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$ROOT_DIR/tools/sbom-license-gate.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

for tool in dpkg-query python3 realpath; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "sbom-license-gate-root: $tool required (run on Linux/docker)" >&2
    exit 1
  fi
done

IMG="$WORKDIR/img"
EV="$WORKDIR/evidence"
mkdir -p "$IMG/var/lib/dpkg" "$IMG/usr/share/doc/bash" "$EV"
: > "$IMG/var/lib/dpkg/available"
cat > "$IMG/var/lib/dpkg/status" <<'STATUS'
Package: bash
Status: install ok installed
Priority: required
Section: shells
Installed-Size: 1
Maintainer: Test <t@example.invalid>
Architecture: amd64
Version: 1.0
Description: fake
 fake

Package: nocopyright
Status: install ok installed
Priority: optional
Section: misc
Installed-Size: 1
Maintainer: Test <t@example.invalid>
Architecture: amd64
Version: 1.0
Description: fake
 fake

Package: abslink
Status: install ok installed
Priority: optional
Section: misc
Installed-Size: 1
Maintainer: Test <t@example.invalid>
Architecture: amd64
Version: 1.0
Description: fake
 fake

Package: rellink
Status: install ok installed
Priority: optional
Section: misc
Installed-Size: 1
Maintainer: Test <t@example.invalid>
Architecture: amd64
Version: 1.0
Description: fake
 fake
STATUS
# abslink: 절대 심볼릭 링크 -> 호스트 파일(이미지 밖). unknown 이어야 한다.
mkdir -p "$IMG/usr/share/doc/abslink"
ln -s /etc/hostname "$IMG/usr/share/doc/abslink/copyright"
# rellink: 이미지 안 상대 링크. 해시되어야 한다.
mkdir -p "$IMG/usr/share/doc/rellink"
ln -s ../bash/copyright "$IMG/usr/share/doc/rellink/copyright"
echo "FAKE-IMAGE-COPYRIGHT" > "$IMG/usr/share/doc/bash/copyright"
expected="$(sha256sum "$IMG/usr/share/doc/bash/copyright" | awk '{print $1}')"

# Run with and without a trailing slash on ROOT, and twice into the same
# EVIDENCE_DIR (rerun must not keep stale lines).
rm -rf "$EV"; mkdir -p "$EV"
echo "stale  usr/share/doc/stale/copyright" > "$EV/copyright-SHA256SUMS"
for root in "$IMG" "$IMG/" "$IMG"; do
  set +e
  ROOT="$root" EVIDENCE_DIR="$EV" OUTPUT="$EV/report.json" bash "$GATE" >"$WORKDIR/out.log" 2>&1
  set -e
  sums="$EV/copyright-SHA256SUMS"
  n="$(wc -l < "$sums" | tr -d ' ')"
  # bash + rellink hashed; nocopyright + abslink unknown.
  if [ "$n" != 2 ]; then
    echo "FAIL (ROOT=$root): expected 2 hash lines, got $n" >&2; cat "$sums" >&2; exit 1
  fi
  if [ "$(awk '{print $1}' "$sums" | sort -u)" != "$expected" ]; then
    echo "FAIL (ROOT=$root): hashes are not the image file's" >&2; cat "$sums" >&2; exit 1
  fi
  if [ "$(awk '{print $2}' "$sums" | tr '\n' ' ')" != "usr/share/doc/bash/copyright usr/share/doc/rellink/copyright " ]; then
    echo "FAIL (ROOT=$root): recorded paths wrong (stale/host/abslink?)" >&2; cat "$sums" >&2; exit 1
  fi
  unknowns="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["unknowns"])' "$EV/report.json")"
  if [ "$unknowns" != 2 ]; then
    echo "FAIL (ROOT=$root): expected unknowns=2, got $unknowns" >&2; cat "$WORKDIR/out.log" >&2; exit 1
  fi
done

echo "sbom-license-gate-root: all scenarios passed"
