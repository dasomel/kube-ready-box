#!/usr/bin/env bash
# release-promote.sh promote 게이트 시나리오 테스트 (#28/#13): security/license 리포트의
# status 와 SHA256SUMS 내용(파일 존재/해시)을 실제로 검사하는지 확인한다.
# RELEASE_DIR 은 임시 디렉터리로 고정하므로 실제 release-evidence 는 건드리지 않는다.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/tools/release-promote.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
export RELEASE_DIR="$WORKDIR/rel"
export VERSION=9.9.9
unset ALLOW_UNKNOWN_EVIDENCE RUN_RUST_VERIFIER ARTIFACT_DIR || true

fail() { echo "FAIL: $*" >&2; exit 1; }

hash_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# 새 candidate 릴리스를 만들고 증거 파일을 채운다. $1=security status, $2=license status
setup() {
  rm -rf "$RELEASE_DIR"
  bash "$SCRIPT" init >/dev/null
  local d="$RELEASE_DIR/$VERSION"
  echo '{"results":[]}' > "$d/verification.json"
  echo '{"bomFormat":"CycloneDX"}' > "$d/sbom.json"
  printf '{"schema_version":1,"status":"%s"}\n' "$1" > "$d/security-report.json"
  printf '{"schema_version":1,"status":"%s"}\n' "$2" > "$d/license-report.json"
  printf '%s  sbom.json\n' "$(hash_of "$d/sbom.json")" > "$d/SHA256SUMS"
}

stage() { grep -m1 '^stage=' "$RELEASE_DIR/$VERSION/release-state.env" | cut -d= -f2-; }

expect_promote() {  # $1=name
  bash "$SCRIPT" promote >"$WORKDIR/out.log" 2>&1 || { cat "$WORKDIR/out.log" >&2; fail "$1: expected promote to succeed"; }
  [ "$(stage)" = staging ] || fail "$1: stage is $(stage), expected staging"
}
expect_blocked() {  # $1=name
  if bash "$SCRIPT" promote >"$WORKDIR/out.log" 2>&1; then fail "$1: expected promote to be blocked"; fi
  [ "$(stage)" = candidate ] || fail "$1: stage changed to $(stage)"
}

setup PASS PASS; expect_promote "all PASS"
setup FAIL PASS; expect_blocked "security FAIL"
setup PASS FAIL; expect_blocked "license FAIL"
setup UNKNOWN PASS; expect_blocked "UNKNOWN"
setup PASS UNKNOWN
ALLOW_UNKNOWN_EVIDENCE=1 bash "$SCRIPT" promote >"$WORKDIR/out.log" 2>&1 || fail "UNKNOWN+opt-in: expected success"
grep -q 'WARNING' "$WORKDIR/out.log" || fail "UNKNOWN+opt-in: expected a warning"
[ "$(stage)" = staging ] || fail "UNKNOWN+opt-in: stage is $(stage)"

setup PASS PASS
echo '{"schema_version":1}' > "$RELEASE_DIR/$VERSION/security-report.json"
expect_blocked "missing status"

setup PASS PASS
printf '%s  nope.bin\n' "$(printf 'a%.0s' $(seq 64))" >> "$RELEASE_DIR/$VERSION/SHA256SUMS"
expect_blocked "SHA256SUMS missing file"

setup PASS PASS
printf '%s  sbom.json\n' "$(printf 'a%.0s' $(seq 64))" > "$RELEASE_DIR/$VERSION/SHA256SUMS"
expect_blocked "SHA256SUMS bad hash"

for evil in "../rel/$VERSION/sbom.json" "$RELEASE_DIR/$VERSION/sbom.json"; do
  setup PASS PASS
  printf '%s  %s\n' "$(hash_of "$RELEASE_DIR/$VERSION/sbom.json")" "$evil" > "$RELEASE_DIR/$VERSION/SHA256SUMS"
  expect_blocked "SHA256SUMS path escape ($evil)"
  grep -q 'escapes artifact dir' "$WORKDIR/out.log" || fail "path escape: wrong reason"
done

# 심볼릭 링크 탈출(파일/디렉터리): 문자열 검사만으로는 통과하므로 realpath 포함 검사가 필요하다.
mkdir -p "$WORKDIR/outside"; echo secret > "$WORKDIR/outside/secret"
setup PASS PASS
d="$RELEASE_DIR/$VERSION"
ln -s "$WORKDIR/outside/secret" "$d/flink"
printf '%s  flink\n' "$(hash_of "$WORKDIR/outside/secret")" > "$d/SHA256SUMS"
expect_blocked "symlink file escape"
grep -q 'escapes artifact dir' "$WORKDIR/out.log" || fail "symlink file: wrong reason"
setup PASS PASS
d="$RELEASE_DIR/$VERSION"
ln -s "$WORKDIR/outside" "$d/dlink"
printf '%s  dlink/secret\n' "$(hash_of "$WORKDIR/outside/secret")" > "$d/SHA256SUMS"
expect_blocked "symlink dir escape"
grep -q 'escapes artifact dir' "$WORKDIR/out.log" || fail "symlink dir: wrong reason"

# CRLF SHA256SUMS 거부
setup PASS PASS
d="$RELEASE_DIR/$VERSION"
printf '%s  sbom.json\r\n' "$(hash_of "$d/sbom.json")" > "$d/SHA256SUMS"
expect_blocked "CRLF SHA256SUMS"

# status 는 trim 하지 않고 정확히 PASS 여야 한다
setup PASS PASS
echo '{"status":" PASS "}' > "$RELEASE_DIR/$VERSION/license-report.json"
expect_blocked "status with spaces"

# 공백만 있는 SHA256SUMS(항목 0개) 거부
setup PASS PASS
printf '  \n\n' > "$RELEASE_DIR/$VERSION/SHA256SUMS"
expect_blocked "whitespace-only SHA256SUMS"

# sha256sum -b 의 '*' 바이너리 마커 허용
setup PASS PASS
d="$RELEASE_DIR/$VERSION"
printf '%s *sbom.json\n' "$(hash_of "$d/sbom.json")" > "$d/SHA256SUMS"
expect_promote "binary marker"

# ARTIFACT_DIR: .box 가 릴리스 디렉터리에 없으면 차단, ARTIFACT_DIR 로 지정하면 통과
setup PASS PASS
d="$RELEASE_DIR/$VERSION"
mkdir -p "$WORKDIR/dist"; echo box > "$WORKDIR/dist/k.box"
printf '%s  k.box\n' "$(hash_of "$WORKDIR/dist/k.box")" > "$d/SHA256SUMS"
expect_blocked "box missing in release dir"
grep -q 'ARTIFACT_DIR' "$WORKDIR/out.log" || fail "missing box: message should mention ARTIFACT_DIR"
ARTIFACT_DIR="$WORKDIR/dist" bash "$SCRIPT" promote >"$WORKDIR/out.log" 2>&1 || { cat "$WORKDIR/out.log" >&2; fail "ARTIFACT_DIR: expected promote to succeed"; }
[ "$(stage)" = staging ] || fail "ARTIFACT_DIR: stage is $(stage)"

echo "release-promote-test: all scenarios passed"
