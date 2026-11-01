#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 dasomel
set -e

echo "=== 03-os-packages-rocky.sh: Install Recommended Packages ==="

# 성능/진단 도구 (EPEL 필요 - 01-base-rocky.sh에서 활성화됨)
echo "Installing essential system packages..."
dnf install -y \
  sysstat \
  iotop \
  iftop \
  nload \
  nethogs

# dool (dstat replacement): 업스트림이 .deb 릴리스만 제공(scottchiefbaker/dool)
# 하므로 rpm 계열에는 이식하지 않는다. EPEL의 dstat은 dool의 후속 fork가 아니라
# 별개 도구라 억지 대체하지 않음 - 공급망을 명확히 남기기 위해 미포함 처리.

# 네트워크 진단 도구 (Ubuntu의 conntrack은 Rocky/EPEL에서 conntrack-tools로 제공)
echo "Installing network diagnostic tools..."
dnf install -y \
  ipvsadm \
  ipset \
  conntrack-tools \
  ethtool \
  tcpdump \
  nmap

# K8s 에코시스템 도구 (Ubuntu의 nfs-common 대응은 nfs-utils)
echo "Installing Kubernetes ecosystem tools..."
dnf install -y \
  jq \
  bzip2 \
  tar \
  bash-completion \
  nfs-utils \
  sshpass

# yq (mikefarah/yq) - YAML processor for K8s manifests
# "latest" 는 빌드 시점마다 달라져 재현 가능한 빌드를 깨뜨린다(#30 공급망 고정).
# YQ_VERSION 으로 고정하고, 필요 시 환경변수로 override 한다. arm64 체크섬은
# Ubuntu용 03-os-packages.sh(및 docs/build-inputs.md)에 이미 검증되어 있는 값을
# 그대로 재사용한다 - yq 바이너리는 배포판 무관 정적 Go 바이너리라 같은
# YQ_VERSION이면 동일 아티팩트/체크섬이다.
echo "Installing yq..."
YQ_VERSION="${YQ_VERSION:-v4.54.1}"
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) YQ_ARCH=amd64; YQ_SHA256="${YQ_SHA256:-8e34fc298390875de416e6a4afcb8cabeceb25d9aa8506c1a2f9353cf702ea5f}" ;;
  aarch64) YQ_ARCH=arm64; YQ_SHA256="${YQ_SHA256:-189088da0c6429ec5178dfaab1a114805f6cab0b61b165ab236efedf1d57a71b}" ;;
  *) echo "No pinned yq checksum for architecture '$ARCH'; refusing to install unverified binary" >&2; exit 1 ;;
esac
curl -sL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${YQ_ARCH}" -o /tmp/yq
echo "${YQ_SHA256}  /tmp/yq" | sha256sum -c -
install -m 755 /tmp/yq /usr/local/bin/yq
rm -f /tmp/yq
echo "  yq $(yq --version) installed"

# eBPF 도구 (EPEL 제공, 옵션)
echo "Installing eBPF tools (if available)..."
dnf install -y \
  bpftrace \
  bcc-tools 2>/dev/null || echo "eBPF tools not available, skipping"

# audit (CIS 벤치마크 대응 - 설치하되 기본 비활성화, Ubuntu auditd와 동일 관행)
echo "Installing audit (installed but disabled by default)..."
dnf install -y audit
sed -i 's/^max_log_file = .*/max_log_file = 50/' /etc/audit/auditd.conf
sed -i 's/^max_log_file_action = .*/max_log_file_action = ROTATE/' /etc/audit/auditd.conf
sed -i 's/^disk_full_action = .*/disk_full_action = SUSPEND/' /etc/audit/auditd.conf
systemctl disable --now auditd 2>/dev/null || true
echo "  -> audit installed but disabled (활성화: systemctl enable --now auditd)"

echo "=== 03-os-packages-rocky.sh: Complete ==="
