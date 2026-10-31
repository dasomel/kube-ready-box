#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
#
# #30 공급망 고정: 새로 추가되는 curl/wget/Packer 플러그인 선언이 floating
# 참조(브랜치 HEAD, "latest", 열린 버전 제약)를 가리키면 CI를 실패시킨다.
# 정적 grep 기반이라 완전하지 않다 — 진짜 checksum 검증 여부까지는 보지
# 않고, "명백히 재현 불가능한 참조" 패턴만 잡는다.
set -euo pipefail

# GUARD_ROOT: 테스트가 fixture 트리를 가리키게 하는 override (기본은 repo root).
ROOT="${GUARD_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
violations=0

report() {
  echo "UNPINNED INPUT: $1" >&2
  violations=$((violations + 1))
}

# 1) curl/wget 이 브랜치 HEAD("/master/", "/main/", "/HEAD/") 또는 GitHub API
#    의 "/releases/latest" 를 직접 가리키는 경우. 주석 라인은 대상이 아니고,
#    "unpinned-guard:allow" 마커가 같은 줄에 있으면 (사후 content 검증 등
#    다른 방식으로 이미 방어된 경우) 의도적으로 건너뛴다.
#    스캔 대상은 원격 입력을 가져올 수 있는 셸이 있는 디렉터리의 명시적 목록이다
#    (repo 전체 스캔은 tests/fixtures/vendored/generated 를 끌어들이므로 피한다;
#    tools/tests 는 일부러 floating URL 을 담고 있어 제외). 새 디렉터리에 fetch
#    스크립트를 추가하면 SCAN_DIRS 에도 추가해야 한다. 줄 끝 "\" 로 이어진 줄은
#    하나로 합쳐 검사하며, 보고하는 줄 번호는 원래 시작 줄이다.
SCAN_DIRS=(packer packer/scripts tools nixos rocky sandbox network storage time security observability etc test-vm scripts .claude/hooks .claude/scripts .codex/hooks)
scan_paths=()
for d in "${SCAN_DIRS[@]}"; do
  [ -d "$ROOT/$d" ] && scan_paths+=("$ROOT/$d")
done
for f in "$ROOT"/*.sh; do
  [ -f "$f" ] && scan_paths+=("$f")
done
while IFS= read -r -d '' f; do
  [ "$f" = "$ROOT/tools/unpinned-input-guard.sh" ] && continue
  while IFS=: read -r lineno line; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    case "$trimmed" in
      '#'*) continue ;;
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
  # bash 가 실제로 잇는 줄만 잇는다. 주석 줄은 잇지 않고 진행 중인 연결을 끝내며,
  # 주석이 들어 있는 줄의 끝 \ 는 bash 에서 줄 잇기가 아니다. 예전에는 "# ... \" 다음
  # 줄의 curl 이 주석으로 합쳐져 통째로 건너뛰어졌다(우회). allow 마커도 합친 명령
  # 전체가 아니라 마커가 있는 물리적 줄에만 적용한다.
  done < <(awk '
    function flush() { if (open && buf ~ /(curl|wget)/) print start ":" buf; buf = ""; open = 0 }
    { t = $0; sub(/^[[:space:]]+/, "", t)
      if (t ~ /^#/) { flush(); next }
      if (!open) { start = NR; open = 1 }
      piece = $0
      if (piece ~ /unpinned-guard:allow/) piece = ""
      if ($0 ~ /\\[[:space:]]*$/ && $0 !~ /(^|[[:space:]])#/) {
        sub(/\\[[:space:]]*$/, " ", piece); buf = buf piece; next
      }
      buf = buf piece; flush() }
    END { flush() }' "$f" 2>/dev/null || true)
done < <(find "${scan_paths[@]}" -type f -name '*.sh' -not -path '*/tests/*' -not -path '*/fixtures/*' -not -path '*/target/*' -print0 2>/dev/null)

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
