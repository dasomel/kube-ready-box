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

# 3. 임시 디렉터리 생성 및 trap 설정
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cd "$tmp_dir"

# release/latest 는 빌드마다 다른 결과를 내는 움직이는 타깃이라 재현 가능한 이미지를
# 만들 수 없다(#7 오프라인 번들, #8 immutable promotion, #10 SBOM 과 직접 충돌).
# GVISOR_RELEASE 로 고정하고, 미지정 시에만 latest 를 쓰되 그 사실을 경고한다.
# 기본값은 실제로 설치·검증한 릴리스로 고정한다. "latest" 는 빌드 시점마다 달라져
# 검증한 것과 배포되는 것이 달라진다(2026-08-21 검증: release-20260817.0, spec 1.2.1).
gvisor_release="${GVISOR_RELEASE:-20260817.0}"
if [ "$gvisor_release" = "latest" ]; then
  echo "[WARN] GVISOR_RELEASE=latest - 빌드 시점마다 결과가 달라지며 재현 가능한 빌드가 아닙니다." >&2
fi
base_url="https://storage.googleapis.com/gvisor/releases/release/${gvisor_release}/${target_arch}"

echo "[INFO] gVisor 릴리스 바이너리 및 체크섬 다운로드 중 ($base_url)..."
curl -sSL -f -O "${base_url}/runsc"
curl -sSL -f -O "${base_url}/runsc.sha512"
curl -sSL -f -O "${base_url}/containerd-shim-runsc-v1"
curl -sSL -f -O "${base_url}/containerd-shim-runsc-v1.sha512"

# 4. 체크섬 검증
echo "[INFO] 다운로드한 바이너리 체크섬(SHA512) 검증 중..."
if ! sha512sum -c runsc.sha512; then
  echo "[ERROR] runsc sha512 체크섬 검증 실패!" >&2
  exit 1
fi

if ! sha512sum -c containerd-shim-runsc-v1.sha512; then
  echo "[ERROR] containerd-shim-runsc-v1 sha512 체크섬 검증 실패!" >&2
  exit 1
fi

echo "[INFO] 체크섬 검증 성공."

# 5. 바이너리 설치
echo "[INFO] /usr/local/bin 에 runsc 및 containerd-shim-runsc-v1 설치 중..."
chmod 0755 runsc containerd-shim-runsc-v1
cp -f runsc containerd-shim-runsc-v1 /usr/local/bin/

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

runsc_version = get_cmd_output([runsc_path, "--version"])
if runsc_version:
    runsc_version = runsc_version.splitlines()[0]

manifest = {
    "schema": "kube-ready-sandbox/v1",
    "sandbox_profile": 1,
    "gvisor_release": gvisor_release,
    "integrity_note": "sha512 checksums fetched from the same origin as the binaries; verifies transfer integrity, not authenticity",
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
    "containerd_configured": containerd_configured,
}

with open(out_path, "w", encoding="utf-8") as f:
    json.dump(manifest, f, sort_keys=True, indent=2)
    f.write("\n")
PY

chmod 0644 /etc/vagrant-box/sandbox-manifest.json
echo "[INFO] /etc/vagrant-box/sandbox-manifest.json 작성 완료."
echo "[INFO] gVisor 샌드박스 런타임 프로비저닝이 완료되었습니다."
