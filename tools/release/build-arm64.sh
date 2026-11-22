#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
#
# 로컬 arm64 릴리스 빌드를 한 번에 하나씩 직렬로 돌린다:
#   build -> 새로 만들어진 .box 검증 -> packer/dist/<릴리스 이름>.box 로 복사.
# 다시 실행해도 안전하다: dist 에 이미 있는 대상은 건너뛴다. 대상마다 한 번 재시도한다
# (mistakes-log #26/#28: 첫 시도가 일시적으로 죽는 경우가 있다).
#
# usage: tools/release/build-arm64.sh [--ubuntu-version 0.3.5] [--rocky-version 0.1.4]
#                                     [--only 'ubuntu 24.04 xfs'] [--dry-run]
#   --only      "<os> <os-version> <fs>" 한 줄과 정확히 일치하는 대상만 (예: 'rocky 9 xfs')
#   --dry-run   빌드 없이 대상/명령만 출력
# 로그: packer/logs/release-<ver>-<os>-<osver>-<fs>-try<N>.out
# exit: 실패한 대상 수(최대 255). 0 이면 전부 dist 에 있다. 사용법 오류는 64.
#
# D1: set -e 를 쓰지 않는다. 재시도 로직이 실패를 값으로 받아야 해서 `set -e` 와 충돌한다.
#     대신 -u/pipefail 만 켜고 모든 실패 경로를 명시적으로 센다.
# D2: 신선도는 mtime 이 아니라 "이번 시도 직전에 만든 stamp 보다 새 파일인가"(-nt)로 본다.
#     이전 빌드의 .box 가 남아 있는데 이번 빌드가 죽은 경우를 성공으로 오인하지 않기 위해서다.
# D3: 두 번째 시도에서도 실패하면 그 대상만 실패로 세고 다음 대상으로 넘어간다
#     (한 대상이 전체 릴리스 빌드를 멈추지 않게). escape hatch: --only 로 하나만 다시 돌린다.
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
UBUNTU_VERSION=""
ROCKY_VERSION=""
ONLY=""
DRY_RUN=0
SEMVER='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'

usage() { sed -n '/^# usage:/,/^# exit:/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
die() { echo "build-arm64: $*" >&2; exit 64; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --ubuntu-version) [ "$#" -ge 2 ] || die "--ubuntu-version needs a value"; UBUNTU_VERSION=$2; shift ;;
    --rocky-version)  [ "$#" -ge 2 ] || die "--rocky-version needs a value"; ROCKY_VERSION=$2; shift ;;
    --only)           [ "$#" -ge 2 ] || die "--only needs a value"; ONLY=$2; shift ;;
    --dry-run)        DRY_RUN=1 ;;
    -h|--help)        usage; exit 0 ;;
    *)                usage >&2; die "unknown option: $1" ;;
  esac
  shift
done
[ -n "$UBUNTU_VERSION$ROCKY_VERSION" ] || { usage >&2; die "give --ubuntu-version and/or --rocky-version"; }
for v in "$UBUNTU_VERSION" "$ROCKY_VERSION"; do
  [ -z "$v" ] || [[ "$v" =~ $SEMVER ]] || die "not a semver: $v"
done

# 대상 목록(나열 순서 = 빌드 순서): "<os> <os-version> <fs> <box-version>"
targets=""
if [ -n "$ROCKY_VERSION" ]; then
  for fs in ext4 xfs; do targets="$targets
rocky 9 $fs $ROCKY_VERSION"; done
fi
if [ -n "$UBUNTU_VERSION" ]; then
  for osver in 24.04 26.04; do
    for fs in ext4 xfs; do targets="$targets
ubuntu $osver $fs $UBUNTU_VERSION"; done
  done
fi

if [ -n "$ONLY" ]; then
  found=0
  while read -r os ver fs _; do
    [ -n "$os" ] || continue
    [ "$os $ver $fs" = "$ONLY" ] && found=1
  done <<LIST
$targets
LIST
  [ "$found" -eq 1 ] || die "--only '$ONLY' matches no target (versions given: ubuntu=${UBUNTU_VERSION:-none} rocky=${ROCKY_VERSION:-none})"
fi

cd "$REPO/packer" || exit 1
[ "$DRY_RUN" -eq 1 ] || mkdir -p dist logs

build_one() { # os osver fs boxver
  local os=$1 ver=$2 fs=$3 bv=$4 src dst try stamp rc
  local args=()
  if [ "$os" = rocky ]; then
    src="output-vagrant/rocky-$ver-$fs-vmware-arm64.box"
    dst="dist/rocky-$ver-$fs-vmware_desktop-arm64-$bv.box"
    args=(--os=rocky vmware-arm64 "--fs=$fs")
  else
    src="output-vagrant/ubuntu-$ver-$fs-vmware-arm64.box"
    dst="dist/ubuntu-$ver-$fs-vmware_desktop-arm64-$bv.box"
    args=(vmware-arm64 "--version=$ver" "--fs=$fs")
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    if [ -s "$dst" ]; then echo "DRYRUN SKIP (exists) $dst"
    else echo "DRYRUN BUILD $os $ver $fs -> $dst: (cd packer && ./build.sh ${args[*]})"; fi
    return 0
  fi
  if [ -s "$dst" ]; then echo "SKIP $dst"; return 0; fi
  for try in 1 2; do
    stamp=$(mktemp)
    echo "=== $(date '+%F %T') BUILD $os $ver $fs try=$try"
    PACKER_LOG=1 ./build.sh "${args[@]}" </dev/null > "logs/release-$bv-$os-$ver-$fs-try$try.out" 2>&1
    rc=$?
    if [ -s "$src" ] && [ "$src" -nt "$stamp" ] && tar -tzf "$src" >/dev/null 2>&1; then
      # APFS clone 이 안 되는 볼륨이면 일반 복사로 내려간다.
      if cp -c "$src" "$dst" 2>/dev/null || cp "$src" "$dst"; then
        echo "=== $(date '+%F %T') OK $dst rc=$rc $(shasum -a 256 "$dst" | cut -d' ' -f1)"
        rm -f "$stamp"; return 0
      fi
    fi
    echo "=== $(date '+%F %T') FAIL $os $ver $fs try=$try rc=$rc"; rm -f "$stamp"
  done
  return 1
}

fails=0
while read -r os ver fs bv; do
  [ -n "$os" ] || continue
  if [ -n "$ONLY" ] && [ "$os $ver $fs" != "$ONLY" ]; then continue; fi
  build_one "$os" "$ver" "$fs" "$bv" || fails=$((fails + 1))
done <<LIST
$targets
LIST
echo "=== DONE fails=$fails"
[ "$fails" -le 255 ] || fails=255
exit "$fails"
