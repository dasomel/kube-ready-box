#!/usr/bin/env bash
# box-catalog.py 테스트: add/no-op, checksum 충돌 실패, --replace, verify, 손상 카탈로그 실패.
# 네트워크/root 불필요. 임시 디렉터리의 가짜 .box 사용.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL="$ROOT/tools/box-catalog.py"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

fail() { echo "box-catalog-test: FAIL: $*" >&2; exit 1; }

C="$WORKDIR/site/boxes/demo.json"
URL="https://example.invalid/releases/download/v1.0.0/demo-1.0.0.box"
printf 'box-one\n' > "$WORKDIR/demo-1.0.0.box"
printf 'box-two\n' > "$WORKDIR/demo-other.box"

add() { # <version> <box> [extra...]
  local v="$1" b="$2"; shift 2
  python3 "$TOOL" add --catalog "$C" --name dasomel/demo --version "$v" \
    --provider vmware_desktop --arch arm64 --url "$URL" --box "$b" "$@"
}

# 1) add
add 1.0.0 "$WORKDIR/demo-1.0.0.box" >/dev/null || fail "initial add"
SUM="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$WORKDIR/demo-1.0.0.box")"
grep -q "$SUM" "$C" || fail "checksum not recorded"

# 2) 동일 재추가는 no-op
cp "$C" "$WORKDIR/before.json"
out="$(add 1.0.0 "$WORKDIR/demo-1.0.0.box")" || fail "identical re-add"
echo "$out" | grep -q 'no-op' || fail "identical re-add not reported as no-op"
cmp -s "$C" "$WORKDIR/before.json" || fail "no-op changed the catalog"

# 3) checksum 충돌은 실패하고 파일을 바꾸지 않는다
if add 1.0.0 "$WORKDIR/demo-other.box" >/dev/null 2>"$WORKDIR/err"; then fail "conflict accepted"; fi
grep -q -- '--replace' "$WORKDIR/err" || fail "conflict message lacks --replace hint"
cmp -s "$C" "$WORKDIR/before.json" || fail "conflict modified the catalog"

# 4) --replace
add 1.0.0 "$WORKDIR/demo-other.box" --replace >/dev/null || fail "--replace"
grep -q "$SUM" "$C" && fail "old checksum still present after --replace"

# 5) 버전은 최신순 정렬 (1.10.0 > 1.2.0 > 1.0.0)
add 1.10.0 "$WORKDIR/demo-1.0.0.box" >/dev/null
add 1.2.0 "$WORKDIR/demo-1.0.0.box" >/dev/null
order="$(python3 -c 'import json,sys;print(" ".join(v["version"] for v in json.load(open(sys.argv[1]))["versions"]))' "$C")"
[ "$order" = "1.10.0 1.2.0 1.0.0" ] || fail "version order: $order"

# 6) verify 통과 (+ box-dir 재해시는 URL 파일명이 같은 단일 항목 카탈로그로)
python3 "$TOOL" verify "$WORKDIR/site/boxes" >/dev/null || fail "verify on valid catalog"
mkdir -p "$WORKDIR/one"
python3 "$TOOL" add --catalog "$WORKDIR/one/one.json" --name dasomel/one --version 1.0.0 \
  --provider vmware_desktop --arch arm64 --url "$URL" --box "$WORKDIR/demo-1.0.0.box" >/dev/null
python3 "$TOOL" verify "$WORKDIR/one" --box-dir "$WORKDIR" >/dev/null || fail "verify --box-dir (match)"
printf 'tampered\n' > "$WORKDIR/demo-1.0.0.box"
if python3 "$TOOL" verify "$WORKDIR/one" --box-dir "$WORKDIR" >/dev/null 2>&1; then
  fail "verify --box-dir accepted a mismatching box"
fi

# 7) 손상된 카탈로그는 verify 실패
for bad in '{not json' \
  '{"name":"a","description":"d","versions":[{"version":"1.0.0","providers":[{"name":"p","url":"http://x/y.box","checksum_type":"sha256","checksum":"abc","architecture":"arm64"}]}]}'; do
  rm -rf "$WORKDIR/bad"; mkdir -p "$WORKDIR/bad"
  printf '%s' "$bad" > "$WORKDIR/bad/x.json"
  if python3 "$TOOL" verify "$WORKDIR/bad" >/dev/null 2>&1; then fail "malformed catalog accepted: $bad"; fi
done

echo "box-catalog-test: all scenarios passed"
