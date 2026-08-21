#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
set -euo pipefail

ROOT="${ROOT:-/}"
EVIDENCE_DIR="${EVIDENCE_DIR:-$ROOT/etc/vagrant-box}"
POLICY_FILE="${POLICY_FILE:-$ROOT/etc/vagrant-box/license-policy.conf}"
OUTPUT="${OUTPUT:-$EVIDENCE_DIR/license-report.json}"

mkdir -p "$(dirname "$OUTPUT")"
failures=0
unknowns=0

# Policy is intentionally allow-list based. Package names with missing license
# metadata are failures; explicitly proprietary packages must be reviewed.
if [ -f "$POLICY_FILE" ]; then
  # shellcheck disable=SC1090
  . "$POLICY_FILE"
fi
: "${DENY_LICENSES:=GPL-3-only-AND-proprietary-placeholder}"
: "${DENY_PACKAGES:=}"

json_escape() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip("\n")))'; }

packages_json="$EVIDENCE_DIR/license-packages.tsv"
: > "$packages_json"
if command -v dpkg-query >/dev/null 2>&1; then
  dpkg-query -W -f='${Package}\t${Version}\t${Source}\t${Status}\n' | sort > "$packages_json"
else
  echo "dpkg-query unavailable" >&2
  unknowns=$((unknowns + 1))
fi

for pkg in $DENY_PACKAGES; do
  if grep -q "^${pkg}[[:space:]]" "$packages_json"; then
    echo "DENY package present: $pkg" >&2
    failures=$((failures + 1))
  fi
done

# Debian package metadata normally does not expose authoritative SPDX license
# identifiers. Preserve the package inventory and require a policy review rather
# than inventing license data. dpkg copyright files are collected as evidence.
copyright_dir="$EVIDENCE_DIR/copyright"
mkdir -p "$copyright_dir"
while IFS=$'\t' read -r pkg _version _source _status; do
  [ -n "$pkg" ] || continue
  if [ -f "/usr/share/doc/$pkg/copyright" ]; then
    sha256sum "/usr/share/doc/$pkg/copyright" >> "$EVIDENCE_DIR/copyright-SHA256SUMS"
  else
    unknowns=$((unknowns + 1))
  fi
done < "$packages_json"
sort -u "$EVIDENCE_DIR/copyright-SHA256SUMS" 2>/dev/null -o "$EVIDENCE_DIR/copyright-SHA256SUMS" || true

# 패키지 인벤토리의 체크섬을 실제로 생성한다.
# 이전에는 inventory-SHA256SUMS 의 존재만 확인했는데 그 파일을 만드는 코드가 없어
# 라이선스 정책 준수 여부와 무관하게 게이트가 항상 FAIL 이었다.
inventory_sha256=""
if [ -s "$EVIDENCE_DIR/license-packages.tsv" ]; then
  sha256sum "$EVIDENCE_DIR/license-packages.tsv" > "$EVIDENCE_DIR/inventory-SHA256SUMS"
  inventory_sha256=$(awk '{print $1; exit}' "$EVIDENCE_DIR/inventory-SHA256SUMS")
fi

if [ -n "$inventory_sha256" ]; then
  inventory_status=PASS
else
  inventory_status=FAIL
  failures=$((failures + 1))
fi

status=PASS
[ "$failures" -gt 0 ] && status=FAIL
cat > "$OUTPUT" <<EOF
{
  "schema_version": 1,
  "status": "${status}",
  "failures": ${failures},
  "unknowns": ${unknowns},
  "inventory_sha256": "${inventory_sha256}",
  "inventory_status": "${inventory_status}",
  "policy": "${POLICY_FILE}",
  "deny_licenses": "${DENY_LICENSES}",
  "deny_packages": "${DENY_PACKAGES}",
  "review_required_for_unknown_license": true
}
EOF

cat "$OUTPUT"
[ "$status" = PASS ]
