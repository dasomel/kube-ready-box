#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
#
# #30 공급망 고정: 새로 추가되는 curl/wget/Packer 플러그인 선언이 floating
# 참조(브랜치 HEAD, "latest", 열린 버전 제약)를 가리키면 CI를 실패시킨다.
# 정적 grep 기반이라 완전하지 않다 — 진짜 checksum 검증 여부까지는 보지
# 않고, "명백히 재현 불가능한 참조" 패턴만 잡는다.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
violations=0

report() {
  echo "UNPINNED INPUT: $1" >&2
  violations=$((violations + 1))
}

# 1) curl/wget 이 브랜치 HEAD("/master/", "/main/", "/HEAD/") 또는 GitHub API
#    의 "/releases/latest" 를 직접 가리키는 경우. 주석 라인은 대상이 아니고,
#    "unpinned-guard:allow" 마커가 같은 줄에 있으면 (사후 content 검증 등
#    다른 방식으로 이미 방어된 경우) 의도적으로 건너뛴다.
while IFS= read -r -d '' f; do
  [ "$f" = "$ROOT/tools/unpinned-input-guard.sh" ] && continue
  while IFS=: read -r lineno line; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    case "$trimmed" in
      '#'*) continue ;;
    esac
    case "$line" in
      *'unpinned-guard:allow'*) continue ;;
    esac
    case "$line" in
      *curl*|*wget*)
        case "$line" in
          *"/master/"*|*"/main/"*|*"/HEAD/"*|*"/releases/latest"*)
            report "$f:$lineno: floating ref in download -- $line"
            ;;
        esac
        ;;
    esac
  done < <(grep -noE '.*(curl|wget).*' "$f" 2>/dev/null || true)
done < <(find "$ROOT/packer/scripts" "$ROOT/tools" -type f -name '*.sh' -print0 2>/dev/null)

# 2) Packer required_plugins 버전 제약이 "=" 정확한 고정이 아니라 열려 있는
#    경우 (">=", ">", "~>" 등).
while IFS= read -r -d '' f; do
  while IFS=: read -r lineno line; do
    case "$line" in
      *'version'*'='*'">='*|*'version'*'='*'">"'*|*'version'*'='*'"~>'*)
        report "$f:$lineno: open-ended plugin version constraint -- $line"
        ;;
    esac
  done < <(grep -noE '^\s*version\s*=.*' "$f" 2>/dev/null || true)
done < <(find "$ROOT/packer" -maxdepth 1 -type f -name '*.pkr.hcl' -print0 2>/dev/null)

if [ "$violations" -gt 0 ]; then
  echo "$violations unpinned/floating build input(s) found. Pin to an exact version/tag and add checksum verification." >&2
  exit 1
fi

echo "No unpinned/floating build inputs found."
