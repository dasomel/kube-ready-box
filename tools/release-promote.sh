#!/usr/bin/env bash
set -euo pipefail
VERSION="${VERSION:-}"
RELEASE_DIR="${RELEASE_DIR:-release-evidence}"
STATE_FILE="$RELEASE_DIR/$VERSION/release-state.env"
[ -n "$VERSION" ] || { echo 'VERSION is required'; exit 2; }
mkdir -p "$RELEASE_DIR/$VERSION"
usage(){ echo "VERSION=vX.Y.Z $0 <init|promote|rollback|verify>"; }
init_release(){
  [ ! -e "$STATE_FILE" ] || { echo "Already initialized: $STATE_FILE" >&2; exit 1; }
  matrix="${PROVIDER_MATRIX:-virtualbox-amd64-ext4,virtualbox-amd64-xfs,virtualbox-arm64-ext4,virtualbox-arm64-xfs,vmware-amd64-ext4,vmware-amd64-xfs,vmware-arm64-ext4,vmware-arm64-xfs}"
  cat > "$STATE_FILE" <<EOF
schema_version=1
version=$VERSION
stage=candidate
created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
required_matrix=$matrix
sbom=required
license_report=required
security_report=required
rollback_policy=retain-last-known-good
EOF
  printf '%s\n' "$matrix" | tr ',' '\n' > "$RELEASE_DIR/$VERSION/required-matrix.txt"
}
promote(){
  grep -q '^stage=candidate$' "$STATE_FILE" || { echo 'Only candidate releases can be promoted'; exit 1; }
  for f in verification.json SHA256SUMS sbom.json security-report.json license-report.json; do
    [ -s "$RELEASE_DIR/$VERSION/$f" ] || { echo "Missing evidence: $f" >&2; exit 1; }
  done
  sed -i.bak 's/^stage=candidate$/stage=staging/' "$STATE_FILE"; rm -f "$STATE_FILE.bak"
  echo "Promoted to staging: $VERSION"
}
rollback(){
  previous="${PREVIOUS_VERSION:-}"
  [ -n "$previous" ] || { echo 'PREVIOUS_VERSION is required' >&2; exit 2; }
  [ -s "$RELEASE_DIR/$previous/release-state.env" ] || { echo "Previous evidence missing: $previous" >&2; exit 1; }
  mkdir -p "$RELEASE_DIR/rollback"
  printf 'schema_version=1\nrolled_back_at=%s\nfrom_version=%s\nto_version=%s\nreason=%s\npolicy=pin-previous-known-good\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$VERSION" "$previous" "${ROLLBACK_REASON:-operator-requested}" > "$RELEASE_DIR/rollback/rollback-pin.env"
  echo "Rollback pin: $VERSION -> $previous (no artifact/tag deletion)"
}
verify(){
  [ -s "$STATE_FILE" ] && grep -q "^version=$VERSION$" "$STATE_FILE" || { echo 'Invalid release state' >&2; exit 1; }
  [ -s "$RELEASE_DIR/$VERSION/required-matrix.txt" ] || { echo 'Missing matrix' >&2; exit 1; }
  echo 'Release metadata verification: PASS'; cat "$STATE_FILE"
}
case "${1:-}" in init) init_release;; promote) promote;; rollback) rollback;; verify) verify;; *) usage; exit 2;; esac
