#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
#
# 릴리스 후보 박스 하나의 게이트: CVE 스캔(scan) + 부팅 검증(boot).
#
# usage: tools/release/verify-candidate.sh [--stage scan|boot|all] [--evidence-dir DIR] [--dry-run] <box-file>
#   <box-file>  <short>-<provider>-<arch>-<version>.box  (short = ubuntu-24.04-ext4 | rocky-9-xfs ...)
#   --stage     기본 all. scan -> boot 순서. all 에서 scan 이 PASS 가 아니면 boot 는 돌리지 않는다(D4).
#   --dry-run   파일 이름 해석과 실행 계획만 출력(박스 파일이 없어도 된다)
#   SCAN_LIMA=krbscan  macOS 에서 스캔을 돌릴 Lima 인스턴스(tools/release/setup-scan-vm.sh 로 만든다)
# 산출물(packer/dist/evidence/): scan-<short>-<arch>.{summary.json,trivy.json,out},
#   catalog/<short>-<arch>.json, boot-<short>-try<N>.log (마지막 줄 boot_rc=<n>)
# exit: 0 = 실행된 단계가 모두 통과(scan 은 PASS 여야 한다), 1 = FAIL, 2 = UNKNOWN/사용법/스캔 불가,
#       3 = 실행된 단계가 하나도 없음(예: amd64 박스에 --stage boot). UNKNOWN 은 성공이 아니다
#       (docs/evidence-contracts.md).
#
# D1: scan 은 박스를 한 줄짜리 후보 카탈로그로 감싸 tools/box-cve-scan.sh 에 넘긴다. 정기 스캔과
#     같은 판정 코드를 쓰기 위해서다. 후보 URL 은 CANDIDATE 태그 자리표시자다(내려받지 않는다).
# D2: 모든 Ubuntu 박스는 VG 이름이 ubuntu-vg 라 한 번에 한 스캔만 가능하다(box-pkgdb-extract.sh).
#     mkdir 잠금으로 호스트에서 직렬화한다. 주인 PID 가 죽었으면 잠금을 가져온다.
# D3: boot 는 vmware_desktop/arm64 만 로컬에서 돈다. 그 외는 "boot=SKIPPED(사유)"를 찍고 PASS 로
#     세지 않는다(amd64 는 build-amd64.yml 의 Boot test 가 증거다).
# D4: all 에서 scan 이 FAIL/UNKNOWN 이면 박스를 다시 빌드해야 하므로 VM 부팅 시간을 쓰지 않는다.
#     escape hatch: --stage boot 로 따로 돌린다.
# D5: boot 로그 번호는 기존 로그 다음 번호다. 재시도 이력이 evidence.py 의 attempts 로 남는다.
#     vagrant 중 어느 단계가 죽어도 마지막 줄에 boot_rc 를 쓰고 VM/임시 박스를 정리한다(trap).
set -uo pipefail

# shellcheck source=tools/release/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
REPO=$(release_repo_root)

STAGE=all
EVIDENCE_DIR=${EVIDENCE_DIR:-$REPO/packer/dist/evidence}
DRY_RUN=0
BOXARG=""
LOCKDIR=${SCAN_LOCK_DIR:-${TMPDIR:-/tmp}/krb-verify-scan.lock}
LOCK_HELD=0

usage() { sed -n '/^# usage:/,/^# exit:/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
die() { echo "verify-candidate: $*" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --stage) [ "$#" -ge 2 ] || die "--stage needs a value"; STAGE=$2; shift ;;
    --evidence-dir) [ "$#" -ge 2 ] || die "--evidence-dir needs a value"; EVIDENCE_DIR=$2; shift ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) usage >&2; die "unknown option: $1" ;;
    *) [ -z "$BOXARG" ] || die "only one box file"; BOXARG=$1 ;;
  esac
  shift
done
case "$STAGE" in scan|boot|all) ;; *) die "--stage must be scan, boot or all" ;; esac
[ -n "$BOXARG" ] || { usage >&2; die "box file required"; }

parsed=$(parse_box_name "$BOXARG") || die "file name is not <short>-<provider>-<arch>-<version>.box: $(basename "$BOXARG")"
read -r SHORT PROVIDER ARCH VERSION <<<"$parsed"
FILE=$(basename "$BOXARG")
if [ "$DRY_RUN" -eq 0 ]; then
  [ -f "$BOXARG" ] || die "box file not found: $BOXARG"
  BOX=$(cd "$(dirname "$BOXARG")" && pwd)/$FILE
else
  BOX=$BOXARG
fi
mkdir -p "$EVIDENCE_DIR" 2>/dev/null || true
EV=$(cd "$EVIDENCE_DIR" 2>/dev/null && pwd || echo "$EVIDENCE_DIR")
CATALOG="$EV/catalog/$SHORT-$ARCH.json"
SUMMARY="$EV/scan-$SHORT-$ARCH.summary.json"
TRIVYJSON="$EV/scan-$SHORT-$ARCH.trivy.json"
SCANOUT="$EV/scan-$SHORT-$ARCH.out"

echo "box: short=$SHORT provider=$PROVIDER arch=$ARCH version=$VERSION file=$FILE"

acquire_lock() {
  local waited=0 max=${SCAN_LOCK_WAIT:-1800} pid
  while ! mkdir "$LOCKDIR" 2>/dev/null; do
    pid=$(cat "$LOCKDIR/pid" 2>/dev/null || true)
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then rm -rf "$LOCKDIR"; continue; fi
    [ "$waited" -lt "$max" ] || return 1
    sleep 5; waited=$((waited + 5))
  done
  echo $$ > "$LOCKDIR/pid"; LOCK_HELD=1
}
release_lock() { [ "$LOCK_HELD" -eq 1 ] && rm -rf "$LOCKDIR"; LOCK_HELD=0; return 0; }
trap release_lock EXIT

json_status() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status",""))' "$1" 2>/dev/null; }

# 러너(Linux 직접 / Lima VM)에서 도는 스캔 스크립트. 값은 printf %q 로 끼워 넣는다.
build_scan_script() { # $1=workdir $2=box $3=catalog $4=pinned trivy version
  printf 'W=%q BOX=%q PROV=%q ARCH=%q REPO=%q CAT=%q PIN=%q\n' "$1" "$2" "$PROVIDER" "$ARCH" "$REPO" "$3" "$4"
  cat <<'EOF'
set -uo pipefail
have=$(trivy --version 2>/dev/null | sed -n '1s/^Version: *//p')
[ "$have" = "$PIN" ] || { echo "UNKNOWN: trivy '$have' != pinned '$PIN' (run tools/release/setup-scan-vm.sh)" >&2; exit 2; }
rm -rf "$W"; mkdir -p "$W"
BOX_FILE=$BOX PROVIDER=$PROV ARCH=$ARCH bash "$REPO/tools/box-cve-scan.sh" "$CAT" "$W"
rc=$?
echo "scan_rc=$rc"
exit $rc
EOF
}

# 반환: 0 PASS, 1 FAIL, 2 UNKNOWN
stage_scan() {
  local pin runner w script rc status
  pin=$(trivy_pin) || { echo "UNKNOWN: cannot read pinned trivy version" >&2; return 2; }
  pin=${pin%% *}
  mkdir -p "$EV/catalog"
  rm -f "$CATALOG" "$SUMMARY" "$TRIVYJSON" "$SCANOUT"   # 이전 결과가 이번 판정으로 읽히면 안 된다
  python3 "$REPO/tools/box-catalog.py" add --catalog "$CATALOG" --name "dasomel/$SHORT" --version "$VERSION" \
    --provider "$PROVIDER" --arch "$ARCH" --box "$BOX" --description candidate \
    --url "https://github.com/dasomel/kube-ready-box/releases/download/CANDIDATE/$FILE" || { echo "UNKNOWN: candidate catalog failed" >&2; return 2; }

  if [ "$(uname -s)" = Linux ]; then
    runner=linux; w="/tmp/krb-scan-$SHORT-$ARCH"
  else
    runner=lima; w="/tmp/krb-scan-$SHORT-$ARCH"
    command -v limactl >/dev/null || { echo "UNKNOWN: limactl not found (macOS needs the scan VM: tools/release/setup-scan-vm.sh)" >&2; return 2; }
    for p in "$BOX" "$CATALOG" "$REPO"; do
      case "$p" in "$HOME"/*) ;; *) echo "UNKNOWN: $p is not under \$HOME, so the Lima VM cannot read it" >&2; return 2 ;; esac
    done
    vm_run true >/dev/null 2>&1 || { echo "UNKNOWN: Lima instance '$SCAN_LIMA' is not running (tools/release/setup-scan-vm.sh)" >&2; return 2; }
  fi
  script=$(build_scan_script "$w" "$BOX" "$CATALOG" "$pin")
  acquire_lock || { echo "UNKNOWN: scan lock busy: $LOCKDIR" >&2; return 2; }
  echo "scan: runner=$runner workdir=$w trivy=$pin"
  { echo "# scan $FILE runner=$runner $(date '+%F %T')"
    if [ "$runner" = linux ]; then bash -c "$script"; else vm_run "$script"; fi
  } 2>&1 | tee "$SCANOUT"
  rc=${PIPESTATUS[0]}
  if [ "$rc" -le 2 ]; then
    if [ "$runner" = linux ]; then
      cp "$w/summary.json" "$SUMMARY" 2>/dev/null; cp "$w/trivy.json" "$TRIVYJSON" 2>/dev/null
    else
      vm_run "cat $(printf %q "$w/summary.json")" > "$SUMMARY" 2>/dev/null || rm -f "$SUMMARY"
      vm_run "cat $(printf %q "$w/trivy.json")" > "$TRIVYJSON" 2>/dev/null || rm -f "$TRIVYJSON"
    fi
  fi
  if [ "$runner" = linux ]; then rm -rf "$w"; else vm_run "sudo rm -rf $(printf %q "$w")" >/dev/null 2>&1; fi
  release_lock
  status=""; [ -s "$SUMMARY" ] && status=$(json_status "$SUMMARY")
  echo "scan: rc=$rc summary_status=${status:-missing}"
  # 판정은 종료 코드와 summary 가 함께 맞을 때만 PASS 다.
  if [ "$rc" -eq 0 ] && [ "$status" = PASS ]; then return 0; fi
  if [ "$rc" -eq 1 ] && [ "$status" = FAIL ]; then return 1; fi
  return 2
}

# boot 단계의 VM 작업. 서브셸에서 set -e 로 돈다. trap 은 어떤 실패에서도 VM/임시 박스를 치운다.
boot_body() { # $1=log number
  set -e
  # D6: EXIT trap 은 함수가 끝난 뒤(서브셸 종료 시) 돈다. local 이면 그때 unbound 라 정리가
  #     실패하고 VM 이 남는다(v0.3.5 실측). 서브셸 전역으로 둔다.
  BOOT_VBOX="krb-candidate/$SHORT"
  BOOT_DIR=$(mktemp -d)
  local d=$BOOT_DIR vbox=$BOOT_VBOX
  cleanup() {
    echo "--- cleanup: destroy VM, remove temp box"
    ( cd "$BOOT_DIR" && vagrant destroy -f ) || true
    vagrant box remove -f --all "$BOOT_VBOX" || true
    rm -rf "$BOOT_DIR"
  }
  trap cleanup EXIT
  cp "$REPO/test-vm/vmware/Vagrantfile" "$d/Vagrantfile"
  cd "$d"
  export VAGRANT_BOX=$vbox
  vagrant box add --force --name "$vbox" --provider vmware_desktop "$BOX"
  vagrant up --provider vmware_desktop
  vagrant upload "$REPO/test-vm/guest-check.sh" /tmp/guest-check.sh
  vagrant ssh -c 'bash /tmp/guest-check.sh'
  vagrant reload
  # shellcheck disable=SC2016 # 게스트에서 확장할 식이다
  vagrant ssh -c 'echo "after_reload state=$(systemctl is-system-running)"; test "$(systemctl --failed --no-legend | wc -l)" -eq 0'
  case "$SHORT" in
    ubuntu-*)
      # build-amd64.yml 과 같다: verify_box 종료 코드가 아니라 failures=0 줄로 판정한다.
      { bash "$REPO/test-vm/verify_box.sh" vmware_desktop --rfp-profile | tee verify.log; } || true
      grep -Eq '^failures=0( |$)' verify.log || { echo "verify_box reported failures (no 'failures=0' line)"; exit 1; }
      ;;
    rocky-*)
      vagrant upload "$REPO/rocky/preflight.sh" /tmp/rocky-preflight.sh
      vagrant ssh -c 'sudo bash /tmp/rocky-preflight.sh'
      ;;
  esac
}

# 반환: 0 PASS, 1 FAIL, 3 SKIPPED
stage_boot() {
  local n=1 log rc
  if [ "$PROVIDER" != vmware_desktop ] || [ "$ARCH" != arm64 ]; then
    echo "boot=SKIPPED(provider=$PROVIDER arch=$ARCH: only vmware_desktop/arm64 boots locally; amd64 boot evidence is the build-amd64.yml run)"
    return 3
  fi
  command -v vagrant >/dev/null || { echo "boot: vagrant not found"; return 1; }
  while [ -e "$EV/boot-$SHORT-try$n.log" ]; do n=$((n + 1)); done
  log="$EV/boot-$SHORT-try$n.log"
  echo "boot: log=$log"
  ( boot_body "$n" ) 2>&1 | tee "$log"
  rc=${PIPESTATUS[0]}
  echo "boot_rc=$rc" | tee -a "$log"
  [ "$rc" -eq 0 ]
}

if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRYRUN stage=$STAGE evidence=$EV pinned-trivy=$(trivy_pin 2>/dev/null || echo unreadable)"
  case "$STAGE" in scan|all)
    echo "DRYRUN scan: catalog=$CATALOG runner=$([ "$(uname -s)" = Linux ] && echo linux || echo "lima:$SCAN_LIMA") lock=$LOCKDIR" ;; esac
  case "$STAGE" in boot|all)
    if [ "$PROVIDER" = vmware_desktop ] && [ "$ARCH" = arm64 ]; then echo "DRYRUN boot: vagrant box krb-candidate/$SHORT, log=$EV/boot-$SHORT-try<N>.log"
    else echo "DRYRUN boot=SKIPPED(provider=$PROVIDER arch=$ARCH)"; fi ;; esac
  exit 0
fi

ran=0; worst=0; scan_res=NOT-RUN; boot_res=NOT-RUN
if [ "$STAGE" = scan ] || [ "$STAGE" = all ]; then
  stage_scan; rc=$?; ran=1
  case "$rc" in 0) scan_res=PASS ;; 1) scan_res=FAIL; worst=1 ;; *) scan_res=UNKNOWN; worst=2 ;; esac
fi
if [ "$STAGE" = boot ] || [ "$STAGE" = all ]; then
  if [ "$STAGE" = all ] && [ "$worst" -ne 0 ]; then
    echo "boot=NOT-RUN(scan was $scan_res; rebuild first)"
  else
    stage_boot; rc=$?
    case "$rc" in
      0) boot_res=PASS; ran=1 ;;
      3) boot_res="SKIPPED" ;;
      *) boot_res=FAIL; ran=1; [ "$worst" -ge 1 ] || worst=1 ;;
    esac
  fi
fi
echo "verify-candidate: $FILE scan=$scan_res boot=$boot_res"
[ "$worst" -eq 0 ] || exit "$worst"
[ "$ran" -eq 1 ] || { echo "verify-candidate: no stage ran, nothing verified" >&2; exit 3; }
exit 0
