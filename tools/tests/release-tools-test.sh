#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
#
# tools/release/{lib,build-arm64,verify-candidate}.sh 의 인자/파일 이름 해석과 거부 경로를 검사한다
# (VM 없이). 실제 scan/boot 단계(Lima, Trivy, VMware)는 여기서 증명하지 않는다.
# - 파일 이름 해석: <short>-<provider>-<arch>-<version>.box, 해석 못 하면 거부
# - build-arm64.sh --dry-run: 대상 목록/--only/버전 검증, 빌드를 시작하지 않는다
# - verify-candidate.sh: 잘못된 이름/없는 파일/없는 단계 거부, amd64 의 boot 는 SKIPPED(PASS 아님)
#   이고 아무 단계도 안 돌았으면 exit 3, scan 은 러너가 없거나 박스가 이상하면 UNKNOWN(exit 2)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
R="$ROOT/tools/release"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# shellcheck source=tools/release/lib.sh
. "$R/lib.sh"

# 1) 파일 이름 해석
[ "$(parse_box_name /x/ubuntu-24.04-ext4-vmware_desktop-arm64-0.3.5.box)" = "ubuntu-24.04-ext4 vmware_desktop arm64 0.3.5" ] || fail "parse ubuntu arm64"
[ "$(parse_box_name rocky-9-xfs-vmware_desktop-arm64-0.1.4.box)" = "rocky-9-xfs vmware_desktop arm64 0.1.4" ] || fail "parse rocky"
[ "$(parse_box_name ubuntu-26.04-xfs-virtualbox-amd64-1.2.3-rc.1.box)" = "ubuntu-26.04-xfs virtualbox amd64 1.2.3-rc.1" ] || fail "parse amd64 prerelease"
for bad in nixos-kube-ready-libvirt-arm64-0.2.3.box ubuntu-24.04-ext4-vmware_desktop-arm64-0.3.box ubuntu-24.04-btrfs-vmware_desktop-arm64-0.3.5.box a.box ubuntu-24.04-ext4-vmware_desktop-arm64-0.3.5.box.tmp; do
  if parse_box_name "$bad" >/dev/null; then fail "parse should reject $bad"; fi
done

# 2) 고정 Trivy 버전은 워크플로에서 읽는다
pin=$(trivy_pin); [[ "$pin" =~ ^[0-9]+\.[0-9]+\.[0-9]+\ [0-9a-f]{64}$ ]] || fail "trivy_pin output: $pin"
grep -q "TRIVY_VERSION: ${pin%% *}\$" "$ROOT/.github/workflows/box-cve-scan.yml" || fail "trivy_pin version differs from workflow"

# 3) build-arm64.sh
out=$(bash "$R/build-arm64.sh" --ubuntu-version 0.3.5 --rocky-version 0.1.4 --dry-run)
[ "$(printf '%s\n' "$out" | grep -c '^DRYRUN BUILD')" = 6 ] || fail "build-arm64: expected 6 targets"
printf '%s\n' "$out" | grep -q 'dist/rocky-9-xfs-vmware_desktop-arm64-0.1.4.box' || fail "build-arm64: rocky release name"
printf '%s\n' "$out" | grep -q 'dist/ubuntu-26.04-ext4-vmware_desktop-arm64-0.3.5.box' || fail "build-arm64: ubuntu release name"
out=$(bash "$R/build-arm64.sh" --ubuntu-version 0.3.5 --only 'ubuntu 24.04 xfs' --dry-run)
[ "$(printf '%s\n' "$out" | grep -c '^DRYRUN BUILD')" = 1 ] || fail "build-arm64: --only should select one target"
for args in "" "--ubuntu-version nope" "--ubuntu-version 0.3.5 --only 'rocky 9 xfs'" "--bogus"; do
  rc=0; eval "bash \"$R/build-arm64.sh\" $args --dry-run" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 64 ] || fail "build-arm64 [$args]: want exit 64, got $rc"
done

# 4) verify-candidate.sh
V="$R/verify-candidate.sh"
rc=0; bash "$V" "$WORK/mystery.box" >/dev/null 2>&1 || rc=$?; [ "$rc" = 2 ] || fail "verify: bad name should exit 2, got $rc"
rc=0; bash "$V" "$WORK/ubuntu-24.04-ext4-vmware_desktop-arm64-0.3.5.box" >/dev/null 2>&1 || rc=$?; [ "$rc" = 2 ] || fail "verify: missing file should exit 2, got $rc"
echo x > "$WORK/ubuntu-24.04-ext4-virtualbox-amd64-0.3.5.box"
rc=0; bash "$V" --stage nope "$WORK/ubuntu-24.04-ext4-virtualbox-amd64-0.3.5.box" >/dev/null 2>&1 || rc=$?; [ "$rc" = 2 ] || fail "verify: bad stage should exit 2, got $rc"
out=$(bash "$V" --dry-run --evidence-dir "$WORK/ev" "$WORK/ubuntu-24.04-ext4-vmware_desktop-arm64-0.3.5.box")
printf '%s\n' "$out" | grep -q 'short=ubuntu-24.04-ext4 provider=vmware_desktop arch=arm64 version=0.3.5' || fail "verify dry-run: parsed fields"
printf '%s\n' "$out" | grep -q 'DRYRUN boot: ' || fail "verify dry-run: arm64 boot plan"
# amd64: boot 는 SKIPPED 이고 PASS 가 아니다. 실행된 단계가 없으면 exit 3.
rc=0; out=$(bash "$V" --stage boot --evidence-dir "$WORK/ev" "$WORK/ubuntu-24.04-ext4-virtualbox-amd64-0.3.5.box" 2>&1) || rc=$?
[ "$rc" = 3 ] || fail "verify: amd64 --stage boot should exit 3, got $rc"
printf '%s\n' "$out" | grep -q 'boot=SKIPPED(provider=virtualbox arch=amd64' || fail "verify: explicit SKIPPED line"
printf '%s\n' "$out" | grep -q 'boot=PASS' && fail "verify: skipped boot must never read PASS"
# scan: 가짜 박스는 어떤 러너에서도 PASS 가 될 수 없다(UNKNOWN/FAIL -> exit != 0), 이전 summary 도 남지 않는다.
mkdir -p "$WORK/ev"; echo '{"status": "PASS"}' > "$WORK/ev/scan-ubuntu-24.04-ext4-amd64.summary.json"
rc=0; SCAN_LOCK_DIR="$WORK/lock" SCAN_LOCK_WAIT=0 bash "$V" --stage scan --evidence-dir "$WORK/ev" "$WORK/ubuntu-24.04-ext4-virtualbox-amd64-0.3.5.box" >/dev/null 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "verify: fake box scan must not pass"
if [ -e "$WORK/ev/scan-ubuntu-24.04-ext4-amd64.summary.json" ] && grep -q '"status": "PASS"' "$WORK/ev/scan-ubuntu-24.04-ext4-amd64.summary.json"; then
  fail "verify: stale PASS summary survived"
fi
# 잠금: 살아 있는 주인이 있으면 UNKNOWN(exit 2)이고 잠금을 훔치지 않는다.
mkdir "$WORK/lock2"; echo $$ > "$WORK/lock2/pid"
rc=0; SCAN_LOCK_DIR="$WORK/lock2" SCAN_LOCK_WAIT=0 bash "$V" --stage scan --evidence-dir "$WORK/ev" "$WORK/ubuntu-24.04-ext4-virtualbox-amd64-0.3.5.box" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] && [ -d "$WORK/lock2" ] || fail "verify: busy lock should exit 2 and stay held (rc=$rc)"
echo "PASS release-tools-test"
