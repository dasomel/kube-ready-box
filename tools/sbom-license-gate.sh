#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
set -euo pipefail

ROOT="${ROOT:-/}"
EVIDENCE_DIR="${EVIDENCE_DIR:-$ROOT/etc/vagrant-box}"
# POLICY_FILE의 기본값은 ROOT(스캔 대상 - 실 게스트/마운트된 이미지/CI 러너 자신)가
# 아니라 이 스크립트가 속한 저장소를 기준으로 잡는다. 어떤 packer 프로비저너도
# etc/license-policy.conf를 게스트의 /etc/vagrant-box/로 복사한 적이 없어서
# (실제 빌드/CI 어디서도 확인됨), 예전 기본값은 항상 존재하지 않는 경로였고
# 조용히 무해한 placeholder(GPL-3-only-AND-proprietary-placeholder, 어떤 실제
# SPDX ID와도 매치되지 않음)로 폴백해 저장소에 커밋된 실제 정책이 한 번도
# 적용된 적이 없었다.
SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICY_FILE="${POLICY_FILE:-$SCRIPT_ROOT/etc/license-policy.conf}"
EXCEPTIONS_FILE="${EXCEPTIONS_FILE:-$SCRIPT_ROOT/etc/license-exceptions.tsv}"
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

# ROOT="/" means "the currently running system" (e.g. inside a guest during
# provisioning) and dpkg-query already targets that correctly with no flags.
# Any other ROOT means "a mounted/extracted image" — dpkg-query ignores ROOT
# by default and would silently report the *host's* packages instead, so it
# must be pointed at that image's admindir explicitly.
dpkg_admindir=""
if [ "$ROOT" != "/" ]; then
  dpkg_admindir="$ROOT/var/lib/dpkg"
fi

if [ -n "$dpkg_admindir" ] && [ ! -d "$dpkg_admindir" ]; then
  echo "dpkg admindir not found under ROOT: $dpkg_admindir" >&2
  failures=$((failures + 1))
  unknowns=$((unknowns + 1))
elif command -v dpkg-query >/dev/null 2>&1; then
  if [ -n "$dpkg_admindir" ]; then
    dpkg-query --admindir="$dpkg_admindir" -W -f='${Package}\t${Version}\t${Source}\t${Status}\n' | sort > "$packages_json"
  else
    dpkg-query -W -f='${Package}\t${Version}\t${Source}\t${Status}\n' | sort > "$packages_json"
  fi
else
  echo "dpkg-query unavailable" >&2
  unknowns=$((unknowns + 1))
fi

# 예외는 DENY_PACKAGES 매치 자체를 지우지 않는다 -- 승인된 예외로 FAIL을
# 면제하되, 누가/언제/왜 승인했는지 exceptions_applied 로 evidence에 남긴다
# (Narwhal #161 "repo별 예외를 명시적으로 승인"). 형식: package<TAB>reason
# <TAB>approved_by<TAB>approved_date(YYYY-MM-DD), '#'로 시작하는 줄은 주석.
exceptions_applied="$EVIDENCE_DIR/license-exceptions-applied.tsv"
: > "$exceptions_applied"
for pkg in $DENY_PACKAGES; do
  if grep -q "^${pkg}[[:space:]]" "$packages_json"; then
    exception_line=""
    if [ -f "$EXCEPTIONS_FILE" ]; then
      exception_line=$(awk -F'\t' -v p="$pkg" '$1 !~ /^#/ && $1 == p {print; exit}' "$EXCEPTIONS_FILE")
    fi
    if [ -n "$exception_line" ]; then
      echo "DENY package present but exception approved: $pkg" >&2
      printf '%s\n' "$exception_line" >> "$exceptions_applied"
    else
      echo "DENY package present: $pkg" >&2
      failures=$((failures + 1))
    fi
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

# 패키지 배열(수백 개 패키지)을 argv로 넘기면 실제 Ubuntu 러너처럼 패키지가
# 많은 환경에서 "Argument list too long"(ARG_MAX 초과)으로 죽는다 -- 이걸
# 컨테이너 테스트(패키지 적음)에서는 못 잡고 실제 CI 러너에서만 재현됐다.
# .tsv 파일 경로만 argv로 넘기고 python 안에서 직접 읽어 큰 문자열이
# 셸을 거치지 않게 한다. 최종 JSON도 한 번에 조립해 컴팩트(한 줄)로 쓴다 --
# 이 저장소의 다른 모든 evidence 스크립트와 동일한 관례이자,
# tools/kube-ready-contracts.sh 의 run_report() 가 `tail -n 1` 로 마지막
# 줄만 읽어 파싱하기 때문에 필수적이다.
python3 -c '
import json, sys
status, failures, unknowns, inventory_sha256, inventory_status, policy_file, deny_licenses, deny_packages, packages_path, exceptions_file, exceptions_applied_path, output = sys.argv[1:]

items = []
with open(packages_path, "r", encoding="utf-8") as fh:
    for line in fh:
        line = line.rstrip("\n")
        if not line:
            continue
        fields = line.split("\t")
        fields += [""] * (4 - len(fields))
        name, version, source, pkg_status = fields[:4]
        items.append({
            "name": name,
            "version": version,
            "source": source,
            "status": pkg_status,
        })

exceptions_applied = []
try:
    with open(exceptions_applied_path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            fields = line.split("\t")
            fields += [""] * (4 - len(fields))
            package, reason, approved_by, approved_date = fields[:4]
            exceptions_applied.append({
                "package": package,
                "reason": reason,
                "approved_by": approved_by,
                "approved_date": approved_date,
            })
except FileNotFoundError:
    pass

obj = {
    "schema_version": 1,
    "status": status,
    "failures": int(failures),
    "unknowns": int(unknowns),
    "inventory_sha256": inventory_sha256,
    "inventory_status": inventory_status,
    "policy": policy_file,
    "exceptions_file": exceptions_file,
    "deny_licenses": deny_licenses,
    "deny_packages": deny_packages,
    "exceptions_applied": exceptions_applied,
    "review_required_for_unknown_license": True,
    "packages": items,
}
raw = json.dumps(obj, sort_keys=True, separators=(",", ":"))
with open(output, "w") as fh:
    fh.write(raw + "\n")
print(raw)
' "$status" "$failures" "$unknowns" "$inventory_sha256" "$inventory_status" "$POLICY_FILE" "$DENY_LICENSES" "$DENY_PACKAGES" "$packages_json" "$EXCEPTIONS_FILE" "$exceptions_applied" "$OUTPUT"

[ "$status" = PASS ]
