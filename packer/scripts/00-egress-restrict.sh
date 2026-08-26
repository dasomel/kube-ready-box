#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
#
# #30 공급망 고정: 빌드 중 outbound 를 필요한 미러/저장소로만 제한한다.
#
# 왜 IP 를 한 번만 resolve 해서 고정하지 않는가: github.com/
# raw.githubusercontent.com/storage.googleapis.com 은 전부 CDN 뒤에 있어
# IP 가 자주 바뀐다. 빌드 시작 시점에 한 번 resolve 한 IP 를 그대로 굳히면,
# 실제 다운로드가 일어나는 시점(수 분 뒤)에 CDN 이 다른 IP 로 옮겨가 있으면
# 빌드가 조용히 막힌다 — 이 세션 내내 잡아온 "조용히 틀린 상태" 와 같은
# 실패 유형이다. 대신 dnsmasq 의 ipset 훅으로, 허용 도메인이 실제로
# resolve 될 때마다(그 시점의 진짜 IP 로, DNS TTL 만큼) ipset 에 자동으로
# 채워 넣는다. iptables 는 그 ipset 의 멤버로만 outbound 를 허용한다.
#
# DNS 조회 자체는 막지 않는다 — 어떤 도메인을 물어보는지 아는 것 자체는
# 공급망 위험이 아니고, 실제 데이터가 오가는 건 그 다음의 TCP/UDP 연결
# 단계이며 그건 ipset 밖의 IP 로는 열리지 않는다.
#
# 이 스크립트는 00 번대로 붙어 이후의 모든 provisioning 스크립트(01~10)
# 보다 먼저 실행돼야 한다. 정리(비활성화)는 99-cleanup.sh 가 담당한다 —
# 빌드 전용 제약이 실제로 배포되는 노드에 그대로 남으면 안 된다.
#
# 알려진 한계: autoinstall(=OS 설치 자체, live-installer/subiquity)이
# 이 스크립트보다 먼저 끝나 있으므로, OS 설치 단계의 apt 접근은 이 제약의
# 적용을 받지 않는다. 이 스크립트가 다루는 것은 00~99 provisioning
# 스크립트 구간뿐이다.
set -euo pipefail

if [ "${RESTRICT_BUILD_EGRESS:-0}" != "1" ]; then
  echo "=== 00-egress-restrict.sh: RESTRICT_BUILD_EGRESS not set to 1, skipping (default: unrestricted build egress) ==="
  exit 0
fi

# 이 스크립트는 00번대 중에서도 가장 먼저 실행돼 첫 부팅 직후에 apt-get을
# 호출한다. cloud-init/subiquity의 후처리(autoremove, unattended-upgrades
# 트리거 등)가 아직 dpkg lock을 쥐고 있을 수 있어, 그걸 기다리지 않으면
# "Could not get lock /var/lib/dpkg/lock-frontend"로 죽는다 -- 01-base.sh
# 가 이미 쓰고 있는 것과 같은 가드.
cloud-init status --wait || true

SET_NAME="kube_ready_build_allowlist"
DNSMASQ_CONF="/etc/dnsmasq.d/kube-ready-egress.conf"
STATE_FILE="/etc/vagrant-box/egress-restrict.state"

ALLOWED_DOMAINS=(
  archive.ubuntu.com
  security.ubuntu.com
  ports.ubuntu.com
  kr.archive.ubuntu.com
  kr.ports.ubuntu.com
  changelogs.ubuntu.com
  github.com
  raw.githubusercontent.com
  objects.githubusercontent.com
  codeload.github.com
  storage.googleapis.com
  time.bora.net
  time.kriss.re.kr
  ntp.kornet.net
  ntp.ubuntu.com
  download.rockylinux.org
  dl.rockylinux.org
  mirrors.rockylinux.org
)

echo "=== 00-egress-restrict.sh: restricting build-time egress to ${#ALLOWED_DOMAINS[@]} allowed domains ==="

apt-get update -qq
apt-get install -y --no-install-recommends dnsmasq ipset

ipset create "$SET_NAME" hash:ip family inet timeout 3600 2>/dev/null || ipset flush "$SET_NAME"

{
  echo "no-resolv"
  echo "server=1.1.1.1"
  echo "server=8.8.8.8"
  echo "listen-address=127.0.0.1"
  echo "bind-interfaces"
  for d in "${ALLOWED_DOMAINS[@]}"; do
    echo "ipset=/${d}/${SET_NAME}"
  done
} > "$DNSMASQ_CONF"

systemctl enable --now dnsmasq
systemctl restart dnsmasq

# 기존 리졸버(예: systemd-resolved via 127.0.0.53)를 우회하고, 로컬
# dnsmasq(127.0.0.1)를 직접 쓰도록 강제한다. 원래 설정은 99-cleanup.sh 가
# 복원한다.
mkdir -p /etc/vagrant-box
cp -a /etc/resolv.conf "${STATE_FILE}.resolv.conf.orig" 2>/dev/null || true
if [ -L /etc/resolv.conf ]; then
  readlink -f /etc/resolv.conf > "${STATE_FILE}.resolv.conf.was_symlink"
fi
rm -f /etc/resolv.conf
echo "nameserver 127.0.0.1" > /etc/resolv.conf

iptables -N KUBE_READY_EGRESS 2>/dev/null || iptables -F KUBE_READY_EGRESS
iptables -C OUTPUT -j KUBE_READY_EGRESS 2>/dev/null || iptables -I OUTPUT -j KUBE_READY_EGRESS

iptables -A KUBE_READY_EGRESS -o lo -j RETURN
iptables -A KUBE_READY_EGRESS -m state --state ESTABLISHED,RELATED -j RETURN
# 로컬 프로세스 -> dnsmasq(127.0.0.1) 질의를 허용한다.
iptables -A KUBE_READY_EGRESS -d 127.0.0.1 -p udp --dport 53 -j RETURN
iptables -A KUBE_READY_EGRESS -d 127.0.0.1 -p tcp --dport 53 -j RETURN
# dnsmasq 자신이 업스트림(1.1.1.1/8.8.8.8)으로 질의를 forward 하는 연결도
# 이 OUTPUT 체인을 그대로 통과해야 하므로, 도메인 이름과 무관하게 그
# 업스트림 리졸버로 가는 DNS 만 별도로 허용한다 -- 실제 데이터 반출 경로가
# 아니라 "어떤 이름을 물어봤는지"만 오가므로 위험이 다르다.
iptables -A KUBE_READY_EGRESS -d 1.1.1.1 -p udp --dport 53 -j RETURN
iptables -A KUBE_READY_EGRESS -d 1.1.1.1 -p tcp --dport 53 -j RETURN
iptables -A KUBE_READY_EGRESS -d 8.8.8.8 -p udp --dport 53 -j RETURN
iptables -A KUBE_READY_EGRESS -d 8.8.8.8 -p tcp --dport 53 -j RETURN
iptables -A KUBE_READY_EGRESS -m set --match-set "$SET_NAME" dst -j RETURN
iptables -A KUBE_READY_EGRESS -j DROP

echo "enabled" > "$STATE_FILE"
echo "=== 00-egress-restrict.sh: complete (allowlist ipset=$SET_NAME, ${#ALLOWED_DOMAINS[@]} domains) ==="
