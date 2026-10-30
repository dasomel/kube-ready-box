#!/usr/bin/env bash
# airgap-bundle.sh verify() 구성 검증 테스트(#7): SHA256SUMS 가 일부만 나열한 번들,
# .deb 누락, ISO 누락/해시 불일치, 미나열 추가 파일이 모두 실패해야 한다.
# 네트워크 없이 합성 번들을 만든다. GNU sha256sum 필요(macOS 는 docker 로 실행).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/tools/airgap-bundle.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

command -v sha256sum >/dev/null || { echo "airgap-bundle-verify-test: sha256sum required (GNU)" >&2; exit 2; }

PKGS="socat conntrack lvm2"
ISO="ubuntu-24.04.3-live-server-amd64.iso"
B="$WORKDIR/build-inputs/ubuntu-24.04/amd64"

make_bundle() {
  rm -rf "$WORKDIR/build-inputs"
  mkdir -p "$B"/{iso,debs,keys,binaries,trivy-db}
  printf 'fake-iso\n' > "$B/iso/$ISO"
  printf 'upstream\n' > "$B/iso/SHA256SUMS.upstream"
  printf 'key\n' > "$B/keys/ubuntu-archive-keyring.gpg"
  : > "$B/packages.txt"
  for p in $PKGS; do
    echo "$p" >> "$B/packages.txt"
    printf 'deb-%s\n' "$p" > "$B/debs/${p}_1.0_amd64.deb"
  done
  cat > "$B/manifest.env" <<EOM
schema_version=1
ubuntu_version=24.04
architecture=amd64
iso_url=https://example.invalid/$ISO
iso_sha256=$(sha256sum "$B/iso/$ISO" | awk '{print $1}')
package_count=3
EOM
  (cd "$B" && find iso debs keys binaries trivy-db -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
}

drop_sum() { (cd "$B" && grep -v "$1" SHA256SUMS > S && mv S SHA256SUMS); }

run_verify() {
  set +e
  BUNDLE_ROOT="$WORKDIR/build-inputs" UBUNTU_VERSION=24.04 ARCH=amd64 bash "$SCRIPT" verify >"$WORKDIR/out.log" 2>&1
  rc=$?
  set -e
  return "$rc"
}

expect_pass() {
  run_verify || { echo "FAIL: $1 should pass" >&2; cat "$WORKDIR/out.log" >&2; exit 1; }
  grep -q 'verification: PASS' "$WORKDIR/out.log" || { echo "FAIL: $1 no PASS line" >&2; exit 1; }
}

expect_fail() {
  if run_verify; then echo "FAIL: $1 should fail" >&2; cat "$WORKDIR/out.log" >&2; exit 1; fi
  grep -q "$2" "$WORKDIR/out.log" || { echo "FAIL: $1 missing message '$2'" >&2; cat "$WORKDIR/out.log" >&2; exit 1; }
  if grep -q 'verification: PASS' "$WORKDIR/out.log"; then echo "FAIL: $1 printed PASS" >&2; exit 1; fi
}

make_bundle; expect_pass "good bundle"

make_bundle; rm "$B/debs/lvm2_1.0_amd64.deb"; drop_sum 'lvm2_'
expect_fail "missing deb" "no .deb in bundle: lvm2"

make_bundle; echo extra > "$B/debs/stray.deb"
expect_fail "extra unlisted file" "not listed in SHA256SUMS: debs/stray.deb"

make_bundle; sed 's/^iso_sha256=.*/iso_sha256=0000/' "$B/manifest.env" > "$B/m" && mv "$B/m" "$B/manifest.env"
expect_fail "ISO hash mismatch" "ISO sha256 does not match manifest"

make_bundle; rm "$B/iso/$ISO"; drop_sum "$ISO"
expect_fail "missing ISO" "ISO named by manifest is missing"

make_bundle; echo tampered > "$B/debs/socat_1.0_amd64.deb"
expect_fail "tampered file" "FAILED"

make_bundle; (cd "$B" && grep keyring SHA256SUMS > S && mv S SHA256SUMS)
expect_fail "keyring-only SHA256SUMS" "not listed in SHA256SUMS"

echo "airgap-bundle-verify-test: all scenarios passed"
