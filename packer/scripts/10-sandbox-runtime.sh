#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

# 1. 기본 빌드 비활성화 체크 (SANDBOX_PROFILE=1 일 때만 동작)
if [ "${SANDBOX_PROFILE:-0}" != "1" ]; then
  echo "[INFO] SANDBOX_PROFILE=1 이 설정되지 않았으므로 gVisor sandbox runtime 설치를 건너뜁니다."
  exit 0
fi

echo "[INFO] SANDBOX_PROFILE=1 감지: gVisor (runsc) 샌드박스 런타임 프로비저닝을 시작합니다."

# 2. 아키텍처 판별
arch="$(uname -m)"
case "$arch" in
  x86_64|amd64)
    target_arch="x86_64"
    ;;
  aarch64|arm64)
    target_arch="aarch64"
    ;;
  *)
    echo "[ERROR] 지원되지 않는 아키텍처입니다: $arch" >&2
    exit 1
    ;;
esac

echo "[INFO] 감지된 아키텍처: $target_arch"

# D-fetch: github.com/<repo>/releases/download/... 가 2026-11-08 에 504 를 반환했다
# (api.github.com 의 release asset 엔드포인트는 정상). 먼저 일반 URL 을 -f + 재시도로
# 받고, 실패하면 API asset 경로로 폴백한다. 비용: 실패 시 API 호출 2회 추가(비인증
# 60회/시간 한도 내). 되돌리기: 폴백 분기를 지우면 이전 동작. 어느 경로든 호출부의
# 고정 SHA-256 검증(sha256sum -c)이 그대로 적용되므로 무결성 검증은 약해지지 않는다.
# (스크립트가 게스트에 개별 업로드되어 공용 파일을 쓸 수 없어 함수를 3개 스크립트에 동일하게 둔다.)
fetch_release_asset() {
  local repo="$1" tag="$2" asset="$3" out="$4" py id
  if curl -fsSL --retry 3 --retry-delay 5 --connect-timeout 20 -o "$out" \
      "https://github.com/${repo}/releases/download/${tag}/${asset}"; then
    return 0
  fi
  rm -f "$out"
  echo "  releases/download failed for ${repo} ${tag} ${asset}; falling back to api.github.com asset API" >&2
  for py in python3 /usr/libexec/platform-python; do
    command -v "$py" >/dev/null 2>&1 && break
    py=""
  done
  if [ -z "$py" ]; then
    echo "  no python3/platform-python available to parse the release JSON" >&2
    return 1
  fi
  id=$(curl -fsSL --retry 3 --retry-delay 5 --connect-timeout 20 \
      "https://api.github.com/repos/${repo}/releases/tags/${tag}" \
    | "$py" -c 'import json,sys
for a in json.load(sys.stdin).get("assets", []):
    if a.get("name") == sys.argv[1]:
        print(a["id"])
        break' "$asset") || id=""
  if [ -z "$id" ]; then
    echo "  asset '${asset}' not found in ${repo} release ${tag}" >&2
    return 1
  fi
  if ! curl -fsSL --retry 3 --retry-delay 5 --connect-timeout 20 \
      -H 'Accept: application/octet-stream' -o "$out" \
      "https://api.github.com/repos/${repo}/releases/assets/${id}"; then
    rm -f "$out"
    return 1
  fi
  echo "  fetched ${asset} via api.github.com asset ${id}" >&2
}

# 3. 임시 디렉터리 생성 및 trap 설정
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cd "$tmp_dir"

# D1: 20261026.0 부터 tarball 만 배포하므로 아키텍처별 SHA-256 을 코드에 고정한다.
# 새 릴리스는 해시 추가 또는 GVISOR_SHA256 지정이 필요하지만, 불일치 시 설치 전에 중단한다.
gvisor_release="${GVISOR_RELEASE:-20261026.0}"
case "${gvisor_release}:${target_arch}" in
  20261026.0:x86_64) pinned_sha256="096589d2d6078ba4caa26aa0200932f571aa5da9d08a5156b98ab1d93fa54468" ;;
  20261026.0:aarch64) pinned_sha256="6b03c9d53f46b5ac56fd32522f38f108645e9f80a26a335e86ad1e09dcdaefda" ;;
  *) pinned_sha256="" ;;
esac
gvisor_sha256="${GVISOR_SHA256:-$pinned_sha256}"
if [ -z "$gvisor_sha256" ]; then
  echo "[ERROR] GVISOR_RELEASE=${gvisor_release} (${target_arch}) 에 고정된 SHA-256 이 없습니다. GVISOR_SHA256 을 지정하세요." >&2
  exit 1
fi
archive="gvisor-${target_arch}.tar.bz2"
base_url="https://github.com/google/gvisor/releases/download/release-${gvisor_release}"

echo "[INFO] gVisor 릴리스 tarball 다운로드 중 (${base_url}/${archive})..."
fetch_release_asset google/gvisor "release-${gvisor_release}" "$archive" "$archive"

# 4. 체크섬 검증 및 필요한 바이너리만 추출
echo "[INFO] 다운로드한 tarball 체크섬(SHA-256) 검증 중..."
if ! echo "${gvisor_sha256}  ${archive}" | sha256sum -c -; then
  echo "[ERROR] gVisor tarball SHA-256 체크섬 검증 실패!" >&2
  exit 1
fi
# D2: gVisor sidecar 는 runsc 옆 gvisor-bin/ 에서 실행된다. 목록을 먼저 검사하고
# 일반 파일만 이름으로 추출한다. 새 릴리스의 구성 변경 시 이 검사를 갱신해야 한다.
tar -tjf "$archive" > archive-members.txt
tar -tvjf "$archive" > archive-listing.txt
mapfile -t archive_members < archive-members.txt
mapfile -t archive_listing < archive-listing.txt
if [ "${#archive_members[@]}" -ne "${#archive_listing[@]}" ]; then
  echo "[ERROR] gVisor tarball 멤버 목록이 일치하지 않습니다." >&2
  exit 1
fi
helper_members=()
for i in "${!archive_members[@]}"; do
  member="${archive_members[$i]}"
  case "$member" in
    gvisor-bin/)
      if [ "${archive_listing[$i]:0:1}" != "d" ]; then
        echo "[ERROR] gvisor-bin/ 멤버가 디렉터리가 아닙니다." >&2
        exit 1
      fi
      ;;
    gvisor-bin/*)
      helper_name="${member#gvisor-bin/}"
      if [[ ! "$helper_name" =~ ^[a-zA-Z0-9._-]+$ || "$helper_name" == "." || "$helper_name" == ".." || "${archive_listing[$i]:0:1}" != "-" ]]; then
        echo "[ERROR] 잘못된 gVisor helper 멤버: $member" >&2
        exit 1
      fi
      helper_members+=("$member")
      ;;
  esac
done
if [ "${#helper_members[@]}" -eq 0 ]; then
  echo "[ERROR] gVisor helper 멤버가 없습니다." >&2
  exit 1
fi
tar -xjf "$archive" -- runsc containerd-shim-runsc-v1 "${helper_members[@]}"
echo "[INFO] 체크섬 검증 및 추출 성공."

# 5. 바이너리 설치
runsc_install_path="/usr/local/bin/runsc"
install_dir="$(dirname "$runsc_install_path")"
echo "[INFO] $install_dir 에 runsc, shim 및 gVisor helper 설치 중..."
rm -rf "$install_dir/gvisor-bin"
mkdir -p "$install_dir/gvisor-bin"
install -m 0755 runsc "$runsc_install_path"
install -m 0755 containerd-shim-runsc-v1 "$install_dir/containerd-shim-runsc-v1"
for member in "${helper_members[@]}"; do
  install -m 0755 "$member" "$install_dir/gvisor-bin/${member#gvisor-bin/}"
done
if [ ! -x "$install_dir/gvisor-bin/gvisor_sentry" ]; then
  echo "[ERROR] gVisor sidecar gvisor_sentry 설치 확인 실패!" >&2
  exit 1
fi

# 6. containerd 런타임 핸들러 설정
# 주의: containerd 는 /etc/containerd/config.toml.d 같은 드롭인 디렉터리를 자동으로
# 읽지 않는다. config.toml 의 imports 지시자로 명시해야 반영된다. 따라서 아래 파일은
# 'containerd 설치 후 병합할 참조 설정'이며, 그 자체로는 활성화되지 않는다.
mkdir -p /etc/containerd/conf.d

cat > /etc/containerd/conf.d/50-runsc.toml <<'EOF'
# containerd 설치 후 /etc/containerd/config.toml 에 아래를 추가하거나
#   imports = ["/etc/containerd/conf.d/*.toml"]
# 를 선언해야 반영된다.
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]
  runtime_type = "io.containerd.runsc.v1"
EOF

containerd_configured="false"
if [ -f /etc/containerd/config.toml ]; then
  if grep -Eq 'runtimes\.runsc|io\.containerd\.runsc\.v1' /etc/containerd/config.toml; then
    echo "[INFO] /etc/containerd/config.toml 에 runsc runtime handler 가 이미 설정되어 있습니다."
    containerd_configured="true"
  else
    echo "[INFO] /etc/containerd/config.toml 에 runsc runtime handler 설정을 추가합니다."
    cat >> /etc/containerd/config.toml <<'EOF'

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]
  runtime_type = "io.containerd.runsc.v1"
EOF
    containerd_configured="true"
  fi
else
  # 이 박스는 컨테이너 런타임을 기본 미포함한다(README "What's NOT Included").
  # containerd 부재는 오류가 아니며, 참조 설정만 남기고 넘어간다.
  echo "[INFO] containerd 미설치 - 참조 설정을 /etc/containerd/conf.d/50-runsc.toml 에 남기고 스킵합니다."
  echo "[INFO] containerd 설치 후 imports 지시자로 병합하거나 'runsc install' 을 실행하세요."
fi

# 7. 오프라인 감사용 sandbox-manifest.json 기록
mkdir -p /etc/vagrant-box

python3 - "$containerd_configured" /etc/vagrant-box/sandbox-manifest.json "$gvisor_release" <<'PY'
import datetime
import json
import os
import subprocess
import sys

containerd_configured = sys.argv[1] == "true"
out_path = sys.argv[2]
gvisor_release = sys.argv[3]

def get_cmd_output(cmd):
    try:
        return subprocess.check_output(cmd, text=True).strip()
    except Exception:
        return ""

def get_file_hash(algo, filepath):
    try:
        return subprocess.check_output([f"{algo}sum", filepath], text=True).split()[0]
    except Exception:
        return ""

runsc_path = "/usr/local/bin/runsc"
shim_path = "/usr/local/bin/containerd-shim-runsc-v1"
helper_dir = os.path.join(os.path.dirname(runsc_path), "gvisor-bin")

runsc_version = get_cmd_output([runsc_path, "--version"])
if runsc_version:
    runsc_version = runsc_version.splitlines()[0]

manifest = {
    "schema": "kube-ready-sandbox/v1",
    "sandbox_profile": 1,
    "gvisor_release": gvisor_release,
    "integrity_note": "release tarball verified against a pinned SHA-256 before extracting binaries",
    "installed_at": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
    "runsc": {
        "path": runsc_path,
        "version": runsc_version,
        "sha256": get_file_hash("sha256", runsc_path),
        "sha512": get_file_hash("sha512", runsc_path),
    },
    "containerd_shim": {
        "path": shim_path,
        "sha256": get_file_hash("sha256", shim_path),
        "sha512": get_file_hash("sha512", shim_path),
    },
    "helpers": [
        {
            "name": name,
            "path": os.path.join(helper_dir, name),
            "sha256": get_file_hash("sha256", os.path.join(helper_dir, name)),
        }
        for name in sorted(os.listdir(helper_dir))
    ],
    "containerd_configured": containerd_configured,
}

with open(out_path, "w", encoding="utf-8") as f:
    json.dump(manifest, f, sort_keys=True, indent=2)
    f.write("\n")
PY

chmod 0644 /etc/vagrant-box/sandbox-manifest.json
echo "[INFO] /etc/vagrant-box/sandbox-manifest.json 작성 완료."
echo "[INFO] gVisor 샌드박스 런타임 프로비저닝이 완료되었습니다."
