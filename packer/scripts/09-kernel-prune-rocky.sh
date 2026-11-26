#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
set -euo pipefail

echo "=== Pruning stale kernels (Rocky) ==="

# Rocky: `dnf -y update` (01-base-rocky.sh) 은 재부팅 없이 실행되므로 빌드 내내
# RUNNING 커널이 설치기 커널이다. dnf 는 실행 중인 커널과 installonly 패키지를
# autoremove 하지 않아 구버전 커널(수백 개 CVE)이 이미지에 남는다. license-info.sh / generate-sbom.sh
# 보다 먼저 실행해 임베디드 SBOM/패키지 목록이 출하되는 커널만 반영하게 한다. 후속
# 스크립트는 구 커널 모듈을 쓰지 않는다.
# 가장 새 커널(RPM 버전 순서)만 남기고 나머지를 제거한다. 하나라도 어긋나면
# 깨진 박스가 배포되지 않도록 빌드를 실패시킨다. 이미 하나뿐이면 no-op.
# BEGIN rocky_prune_old_kernels
rocky_prune_old_kernels() {
  local newest old default_kernel remaining
  newest="$(python3 -I - <<'PY'
import functools, rpm
hdrs = list(rpm.TransactionSet().dbMatch('name', 'kernel-core'))
def key(h):
    return (str(h['epoch'] or 0), h['version'], h['release'])
if hdrs:
    best = max(hdrs, key=functools.cmp_to_key(lambda a, b: rpm.labelCompare(key(a), key(b))))
    print('%s-%s.%s' % (best['version'], best['release'], best['arch']))
PY
)" || true
  if [ -z "$newest" ]; then
    echo "ERROR: cannot determine newest installed kernel-core" >&2
    return 1
  fi

  old="$(rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE}.%{ARCH} %{NEVRA}\n' \
    | awk -v n="$newest" '$1 ~ /^kernel(-core|-modules|-modules-core|-modules-extra|-modules-internal|-devel|-devel-matched)?$/ && $2 != n {print $3}')"
  if [ -n "$old" ]; then
    echo "Removing stale kernels (keeping $newest):"
    echo "$old"
    # 실행 중 커널 보호를 끈다(빌드 중 RUNNING 커널 = 구 커널).
    # shellcheck disable=SC2086
    dnf -y remove --setopt=protect_running_kernel=False \
      --setopt=clean_requirements_on_remove=False $old
  fi

  remaining="$(rpm -q kernel-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n')"
  if [ "$remaining" != "$newest" ]; then
    echo "ERROR: expected only kernel-core $newest, found: $remaining" >&2
    return 1
  fi
  if ! command -v grubby >/dev/null 2>&1; then
    echo "ERROR: grubby not found; cannot verify bootloader default" >&2
    return 1
  fi
  default_kernel="$(grubby --default-kernel 2>/dev/null || true)"
  if [ "$default_kernel" != "/boot/vmlinuz-$newest" ]; then
    echo "Default boot kernel is '$default_kernel'; setting /boot/vmlinuz-$newest"
    grubby --set-default "/boot/vmlinuz-$newest"
    default_kernel="$(grubby --default-kernel 2>/dev/null || true)"
    if [ "$default_kernel" != "/boot/vmlinuz-$newest" ]; then
      echo "ERROR: bootloader default '$default_kernel' != /boot/vmlinuz-$newest" >&2
      return 1
    fi
  fi
  echo "  -> only kernel $newest remains and is the boot default"
}
# END rocky_prune_old_kernels

rocky_prune_old_kernels
