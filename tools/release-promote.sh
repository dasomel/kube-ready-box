#!/usr/bin/env bash
set -euo pipefail
VERSION="${VERSION:-}"
RELEASE_DIR="${RELEASE_DIR:-release-evidence}"
STATE_FILE="$RELEASE_DIR/$VERSION/release-state.env"
[ -n "$VERSION" ] || { echo 'VERSION is required'; exit 2; }
usage(){ echo "VERSION=vX.Y.Z $0 <init|promote|rollback|verify>"; }

# release-state.env 는 init에서만 생성한다. init 이외의 하위 명령은 반드시
# 이미 존재하는 상태 파일을 요구하고, 없으면 명확한 메시지로 실패한다.
# (이전에는 여기서 무조건 mkdir을 해서 usage/에러 경로에서도 빈 디렉터리가 남았다)
require_state(){
  [ -s "$STATE_FILE" ] || { echo "Release not initialized: $STATE_FILE (run: VERSION=$VERSION $0 init)" >&2; exit 1; }
}

get_field(){
  # release-state.env 에서 key=value 한 줄을 읽어 값만 반환한다.
  # 키가 없으면 빈 문자열을 반환하고 0으로 끝난다. grep 의 1을 그대로 흘리면
  # 호출부의 bare 대입이 set -e 에 걸려, 아래 준비된 '<missing>' 분기에
  # 도달하지 못하고 아무 메시지 없이 죽는다.
  local line
  line=$(grep -m1 "^$1=" "$STATE_FILE" || true)
  printf '%s\n' "${line#*=}"
}

# SHA256SUMS는 JSON이 아니라 체크섬 목록이므로 구조적으로 검증한다.
# 유효하지 않으면 위반한 줄 번호와 내용을 stdout으로 출력하고 1을 반환한다.
validate_sha256sums(){
  local f="$1" lineno=0 line
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno+1))
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    if ! [[ "$line" =~ ^[0-9a-f]{64}[\ \*][\ ]?[^[:space:]] ]]; then
      echo "line $lineno: $line"
      return 1
    fi
  done < "$f"
  return 0
}

# JSON evidence 파일 파싱. 유효하지 않으면 파이썬 에러 마지막 줄을 stdout으로 출력한다.
validate_json(){
  local f="$1" err
  if err=$(python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" 2>&1); then
    return 0
  fi
  printf '%s\n' "$err" | tail -1
  return 1
}

# 5개 evidence 파일 중 하나를 검사한다. 유효하면 아무것도 출력하지 않고 0을 반환,
# 무효/누락이면 사유를 stdout에 출력하고 1을 반환한다.
evidence_error(){
  local path="$1" base detail
  base=$(basename "$path")
  if [ ! -s "$path" ]; then
    echo "missing"
    return 1
  fi
  if [ "$base" = "SHA256SUMS" ]; then
    if detail=$(validate_sha256sums "$path"); then return 0; fi
    echo "invalid ($detail)"
    return 1
  fi
  if detail=$(validate_json "$path"); then return 0; fi
  echo "invalid JSON ($detail)"
  return 1
}

evidence_valid(){ evidence_error "$1" >/dev/null; }

EVIDENCE_FILES="verification.json SHA256SUMS sbom.json security-report.json license-report.json"

# promote 단계 전용: 하나라도 무효/누락이면 즉시 종료한다.
validate_all_evidence(){
  local f path reason
  for f in $EVIDENCE_FILES; do
    path="$RELEASE_DIR/$VERSION/$f"
    if ! reason=$(evidence_error "$path"); then
      echo "Missing/invalid evidence: $f ($reason)" >&2
      exit 1
    fi
  done
}

# verification.json을 required-matrix.txt와 대조한다.
# verification.json은 두 형태를 모두 허용한다:
#   {"results": [{"target": "...", "status": "PASS"}, ...]}
#   {"cases":   [{"target": "...", "status": "PASS"}, ...]}   (test-vm/matrix.sh 산출물)
# target이 없는 case는 어떤 required target도 충족하지 못한다.
# 표준출력 1번째 줄: "<passed>/<total>", 이후 줄(있다면): 미달성 target 이름.
matrix_eval(){
  local verification_file="$1" matrix_file="$2"
  python3 - "$verification_file" "$matrix_file" <<'PY'
import json, sys
verification_path, matrix_path = sys.argv[1:3]
with open(matrix_path) as f:
    required = [line.strip() for line in f if line.strip()]
try:
    with open(verification_path) as f:
        data = json.load(f)
except Exception:
    data = {}
items = data.get('results')
if items is None:
    items = data.get('cases', [])
if not isinstance(items, list):
    items = []
passed = set()
for item in items:
    if not isinstance(item, dict):
        continue
    target = item.get('target')
    if not target:
        continue
    if str(item.get('status', '')).upper() == 'PASS':
        passed.add(target)
missing = [t for t in required if t not in passed]
print(f"{len(required) - len(missing)}/{len(required)}")
for t in missing:
    print(t)
PY
}

# staging -> production 게이트: matrix가 100% PASS가 아니면 미달성 target을 나열하고 종료한다.
check_matrix_full(){
  local matrix_file="$RELEASE_DIR/$VERSION/required-matrix.txt"
  [ -s "$matrix_file" ] || { echo "Missing required-matrix.txt" >&2; exit 1; }
  local lines=() line
  while IFS= read -r line; do
    lines+=("$line")
  done < <(matrix_eval "$RELEASE_DIR/$VERSION/verification.json" "$matrix_file")
  if [ "${#lines[@]}" -gt 1 ]; then
    echo "Matrix coverage incomplete (${lines[0]}); missing targets: ${lines[*]:1}" >&2
    exit 1
  fi
}

# stage 전이를 실행하고 promotion-log.tsv(UTC 타임스탬프, from_stage, to_stage)에 기록한다.
transition_stage(){
  local new_stage="$1" old_stage ts
  old_stage=$(get_field stage)
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  sed -i.bak "s/^stage=.*/stage=$new_stage/" "$STATE_FILE"; rm -f "$STATE_FILE.bak"
  printf '%s\t%s\t%s\n' "$ts" "$old_stage" "$new_stage" >> "$RELEASE_DIR/$VERSION/promotion-log.tsv"
  echo "Promoted $VERSION: $old_stage -> $new_stage"
}

init_release(){
  mkdir -p "$RELEASE_DIR/$VERSION"
  [ ! -e "$STATE_FILE" ] || { echo "Already initialized: $STATE_FILE" >&2; exit 1; }
  local matrix
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
  echo "Initialized release $VERSION (stage=candidate)"
}

# 3단계 상태 기계: candidate -> staging -> production. production과 rolled_back은
# 종착 상태이므로 승격을 거부한다. 알 수 없는 stage도 거부한다.
promote(){
  local stage
  stage=$(get_field stage)
  case "$stage" in
    candidate)
      validate_all_evidence
      transition_stage staging
      ;;
    staging)
      validate_all_evidence
      check_matrix_full
      transition_stage production
      ;;
    production)
      echo "Cannot promote '$VERSION': already at terminal stage 'production'" >&2
      exit 1
      ;;
    rolled_back)
      echo "Cannot promote '$VERSION': stage is 'rolled_back' (terminal)" >&2
      exit 1
      ;;
    *)
      echo "Cannot promote '$VERSION': unknown stage '${stage:-<missing>}'" >&2
      exit 1
      ;;
  esac
}

rollback(){
  local previous="${PREVIOUS_VERSION:-}"
  [ -n "$previous" ] || { echo 'PREVIOUS_VERSION is required' >&2; exit 2; }
  local prev_state="$RELEASE_DIR/$previous/release-state.env"
  [ -s "$prev_state" ] || { echo "Previous evidence missing: $previous" >&2; exit 1; }

  # 롤백 대상은 반드시 한 번이라도 검증을 통과한 known-good이어야 한다.
  # candidate로는 롤백할 수 없다 (검증되지 않은 버전을 "안전한 이전 버전"으로 취급하지 않기 위함).
  local prev_stage
  prev_stage=$(grep -m1 '^stage=' "$prev_state" | cut -d= -f2-)
  case "$prev_stage" in
    staging|production) ;;
    *) echo "Cannot rollback to '$previous': stage is '${prev_stage:-<missing>}', must be a known-good (staging or production)" >&2; exit 1;;
  esac

  local current_stage reason ts
  current_stage=$(get_field stage)
  reason="${ROLLBACK_REASON:-operator-requested}"
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  mkdir -p "$RELEASE_DIR/rollback"
  # rollback-pin.env는 "현재 pin" 단일 값을 유지한다 (docs/DEPLOY_CHECKLIST.md가 이 경로를 참조).
  printf 'schema_version=1\nrolled_back_at=%s\nfrom_version=%s\nto_version=%s\nreason=%s\npolicy=pin-previous-known-good\n' "$ts" "$VERSION" "$previous" "$reason" > "$RELEASE_DIR/rollback/rollback-pin.env"
  # history.tsv는 불변 이력이다: 롤백마다 한 줄씩 누적된다.
  printf '%s\t%s\t%s\t%s\n' "$ts" "$VERSION" "$previous" "$reason" >> "$RELEASE_DIR/rollback/history.tsv"

  # 롤백된 버전 자신의 상태에도 흔적을 남긴다: 더 이상 "정상 운영중"이 아님을 기록.
  sed -i.bak "s/^stage=.*/stage=rolled_back/" "$STATE_FILE"; rm -f "$STATE_FILE.bak"
  printf '%s\t%s\t%s\n' "$ts" "$current_stage" "rolled_back" >> "$RELEASE_DIR/$VERSION/promotion-log.tsv"

  echo "Rollback pin: $VERSION -> $previous (no artifact/tag deletion)"
}

verify(){
  local errors=0 schema version stage candidate_evidence_ok=0
  schema=$(get_field schema_version)
  version=$(get_field version)
  stage=$(get_field stage)

  echo "=== Release verify: $VERSION ==="

  if [ "$schema" = "1" ]; then echo "PASS schema_version=$schema"; else echo "FAIL schema_version: expected 1, got '${schema:-<missing>}'" >&2; errors=1; fi
  if [ "$version" = "$VERSION" ]; then echo "PASS version=$version"; else echo "FAIL version mismatch: state has '${version:-<missing>}'" >&2; errors=1; fi
  case "$stage" in
    candidate|staging|production|rolled_back) echo "PASS stage=$stage";;
    *) echo "FAIL unknown stage: '${stage:-<missing>}'" >&2; errors=1;;
  esac

  local matrix_file="$RELEASE_DIR/$VERSION/required-matrix.txt"
  if [ -s "$matrix_file" ]; then echo "PASS required-matrix.txt present"; else echo "FAIL required-matrix.txt missing" >&2; errors=1; fi

  case "$stage" in
    candidate)
      # candidate 단계에서는 evidence가 아직 필수가 아니다. 준비 상태만 보고하고,
      # evidence가 부족해도 메타데이터가 온전하면 exit 0 — 단, "PASS"로 오독되지 않게 한다.
      local f evidence_ok=0
      for f in $EVIDENCE_FILES; do
        evidence_valid "$RELEASE_DIR/$VERSION/$f" && evidence_ok=$((evidence_ok+1))
      done
      candidate_evidence_ok=$evidence_ok
      echo "INFO evidence: $evidence_ok/5 present-and-valid"
      if [ -s "$matrix_file" ]; then
        local lines=() line
        while IFS= read -r line; do lines+=("$line"); done < <(matrix_eval "$RELEASE_DIR/$VERSION/verification.json" "$matrix_file")
        echo "INFO matrix: ${lines[0]:-0/0} PASS"
      fi
      if [ "$evidence_ok" -eq 5 ]; then
        echo "INFO promotable to staging: yes (evidence complete)"
      else
        echo "INFO promotable to staging: no (evidence $evidence_ok/5)"
      fi
      ;;
    staging|production)
      # staging/production은 evidence가 이미 존재해야 정상이다. 없으면 게이트가
      # 우회된 것이므로 반드시 실패로 보고한다.
      local f reason
      for f in $EVIDENCE_FILES; do
        if ! reason=$(evidence_error "$RELEASE_DIR/$VERSION/$f"); then
          echo "FAIL evidence: $f ($reason)" >&2
          errors=1
        fi
      done
      if [ "$stage" = production ] && [ -s "$matrix_file" ]; then
        local lines=() line
        while IFS= read -r line; do lines+=("$line"); done < <(matrix_eval "$RELEASE_DIR/$VERSION/verification.json" "$matrix_file")
        echo "INFO matrix: ${lines[0]:-0/0} PASS"
        if [ "${#lines[@]}" -gt 1 ]; then
          echo "FAIL matrix coverage incomplete; missing targets: ${lines[*]:1}" >&2
          errors=1
        fi
      fi
      ;;
    rolled_back)
      echo "INFO stage is terminal (rolled_back); evidence not re-checked"
      ;;
  esac

  if [ "$errors" -eq 0 ]; then
    if [ "$stage" = candidate ] && [ "${candidate_evidence_ok:-0}" -lt 5 ]; then
      echo "Release metadata verification: PASS (evidence ${candidate_evidence_ok:-0}/5 - not promotable)"
    else
      echo "Release metadata verification: PASS"
    fi
  else
    echo "Release metadata verification: FAIL" >&2
    exit 1
  fi
}

case "${1:-}" in
  init) init_release;;
  promote) require_state; promote;;
  rollback) require_state; rollback;;
  verify) require_state; verify;;
  *) usage; exit 2;;
esac
