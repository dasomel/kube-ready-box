#!/usr/bin/env bash
# fetch_release_asset (PR #102) 테스트: 3개 스크립트 본문 동일성(drift guard), PATH-shim curl 로
# primary 성공 / API fallback / 자산 없음 / API 다운로드 실패 / 인터프리터 없음, 그리고
# 변조된 fallback 바이트가 고정 SHA-256 검증에서 설치 전에 fail-closed 되는지 확인. 네트워크 불필요.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

fail() { echo "fetch-release-asset-test: FAIL: $*" >&2; exit 1; }
sha() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

SCRIPTS=(
  packer/scripts/03-os-packages.sh
  packer/scripts/03-os-packages-rocky.sh
  packer/scripts/10-sandbox-runtime.sh
)

# 1) drift guard: 함수 본문(컬럼 0 의 `}` 까지)이 세 스크립트에서 byte-identical 이어야 한다.
extract() { awk '/^fetch_release_asset\(\) \{/{p=1} p{print} p&&/^}/{exit}' "$ROOT/$1"; }
for s in "${SCRIPTS[@]}"; do
  extract "$s" > "$WORKDIR/$(basename "$s").fn"
  [ -s "$WORKDIR/$(basename "$s").fn" ] || fail "fetch_release_asset not found in $s"
  tail -n1 "$WORKDIR/$(basename "$s").fn" | grep -qx '}' || fail "unterminated function in $s"
done
for s in "${SCRIPTS[@]:1}"; do
  cmp -s "$WORKDIR/$(basename "${SCRIPTS[0]}").fn" "$WORKDIR/$(basename "$s").fn" \
    || fail "fetch_release_asset drifted: ${SCRIPTS[0]} vs $s"
done
FN="$WORKDIR/fn.sh"
cp "$WORKDIR/$(basename "${SCRIPTS[0]}").fn" "$FN"
echo "ok drift guard (${#SCRIPTS[@]} scripts identical)"

# 2) PATH-shim curl. 모드는 환경변수로 제어한다.
SHIM="$WORKDIR/shim"; mkdir -p "$SHIM"
cat > "$SHIM/curl" <<'SH'
#!/bin/bash
out=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -H|--retry|--retry-delay|--connect-timeout) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
case "$url" in
  */releases/download/*)
    [ "${FAKE_PRIMARY:-fail}" = ok ] || exit 22
    printf '%s' "$FAKE_PRIMARY_BYTES" > "$out" ;;
  */releases/tags/*)
    printf '{"assets":[{"name":"other.tgz","id":7},{"name":"tool.tgz","id":42}]}' ;;
  */releases/assets/42)
    if [ "${FAKE_API_ASSET:-ok}" = fail ]; then printf 'partial' > "$out"; exit 22; fi
    printf '%s' "$FAKE_API_BYTES" > "$out" ;;
  *) exit 22 ;;
esac
SH
chmod +x "$SHIM/curl"
# 인터프리터 없는 PATH: curl shim + rm 만 노출 (function 이 쓰는 외부 명령)
NOPY="$WORKDIR/nopy"; mkdir -p "$NOPY"
cp "$SHIM/curl" "$NOPY/curl"; ln -s "$(command -v rm)" "$NOPY/rm"

GOOD='good-bytes'
run() { # <PATH> <asset> <out>  (stderr -> $WORKDIR/err)
  # shellcheck source=/dev/null
  ( export PATH="$1"; source "$FN"; fetch_release_asset acme/tool v1 "$2" "$3" ) 2>"$WORKDIR/err"
}
export FAKE_PRIMARY_BYTES="$GOOD" FAKE_API_BYTES="$GOOD"
P="$SHIM:$PATH"

# primary 성공
out="$WORKDIR/o1"; FAKE_PRIMARY=ok run "$P" tool.tgz "$out" || fail "primary success returned non-zero"
[ "$(cat "$out")" = "$GOOD" ] || fail "primary content"
if grep -q 'falling back' "$WORKDIR/err"; then fail "primary success must not fall back"; fi
echo "ok primary success"

# primary 실패 -> API fallback 성공
out="$WORKDIR/o2"; FAKE_PRIMARY=fail run "$P" tool.tgz "$out" || fail "fallback returned non-zero"
[ "$(cat "$out")" = "$GOOD" ] || fail "fallback content"
grep -q 'api.github.com asset 42' "$WORKDIR/err" || fail "fallback log missing"
echo "ok primary fail -> API fallback"

# 릴리스에 없는 자산
out="$WORKDIR/o3"
if FAKE_PRIMARY=fail run "$P" missing.tgz "$out"; then fail "missing asset must fail"; fi
[ ! -e "$out" ] || fail "output left for missing asset"
grep -q "not found" "$WORKDIR/err" || fail "missing asset message"
echo "ok asset not in release"

# API 자산 다운로드 실패 (partial 파일 제거)
out="$WORKDIR/o4"
if FAKE_PRIMARY=fail FAKE_API_ASSET=fail run "$P" tool.tgz "$out"; then fail "API download failure must fail"; fi
[ ! -e "$out" ] || fail "partial file left after API failure"
echo "ok API download failure leaves no file"

# python3/platform-python 없음
if [ -e /usr/libexec/platform-python ]; then
  echo "skip no-interpreter case: /usr/libexec/platform-python exists on this host"
else
  out="$WORKDIR/o5"
  if FAKE_PRIMARY=fail run "$NOPY" tool.tgz "$out"; then fail "no interpreter must fail"; fi
  [ ! -e "$out" ] || fail "output left without interpreter"
  grep -q 'no python3/platform-python' "$WORKDIR/err" || fail "no-interpreter message"
  echo "ok no interpreter"
fi

# 3) fail-closed 통합: 실제 호출부 패턴, fallback 경로에서 변조된 바이트
printf '%s' "$GOOD" > "$WORKDIR/ref"
PINNED="$(sha "$WORKDIR/ref")"
cat > "$WORKDIR/callsite.sh" <<CALLSITE
set -euo pipefail
source "$FN"
cd "$WORKDIR"
rm -f file.tgz
fetch_release_asset acme/tool v1 tool.tgz file.tgz
if command -v sha256sum >/dev/null; then echo "$PINNED  file.tgz" | sha256sum -c -; else echo "$PINNED  file.tgz" | shasum -a 256 -c -; fi
echo INSTALL-RAN
CALLSITE
export PATH="$P"
# 정상 바이트: 설치 단계 도달
res="$(FAKE_PRIMARY=fail bash "$WORKDIR/callsite.sh" 2>/dev/null)" || fail "untampered call-site failed"
[[ "$res" == *INSTALL-RAN* ]] || fail "install step not reached for good bytes"
# 변조 바이트: 설치 전에 중단
rc=0
res="$(FAKE_PRIMARY=fail FAKE_API_BYTES='tampered' bash "$WORKDIR/callsite.sh" 2>/dev/null)" || rc=$?
[ "$rc" -ne 0 ] || fail "tampered fallback bytes must exit non-zero"
[[ "$res" != *INSTALL-RAN* ]] || fail "install step ran despite checksum mismatch"
echo "ok fail-closed on tampered fallback bytes"

echo "fetch-release-asset-test: PASS"
