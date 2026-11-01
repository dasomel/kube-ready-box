#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 dasomel
set -e

echo "=== Final Cleanup for Kube-ready Box ==="

# 00-egress-restrict.sh 가 남긴 빌드 전용 outbound 제약을 되돌린다. 배포되는
# 노드는 이 제약 없이 정상적으로 임의 DNS/네트워크를 쓸 수 있어야 한다 -
# 다른 정리 단계보다 먼저 실행해서, 이후 단계가 실패해도 최소한 이 상태는
# 원복되게 한다.
if [ -f /etc/vagrant-box/egress-restrict.state ]; then
  echo "Reverting build-time egress restriction..."
  iptables -D OUTPUT -j KUBE_READY_EGRESS 2>/dev/null || true
  iptables -F KUBE_READY_EGRESS 2>/dev/null || true
  iptables -X KUBE_READY_EGRESS 2>/dev/null || true
  ipset destroy kube_ready_build_allowlist 2>/dev/null || true
  rm -f /etc/dnsmasq.d/kube-ready-egress.conf
  systemctl disable --now dnsmasq 2>/dev/null || true
  apt-get purge -y dnsmasq ipset 2>/dev/null || true
  if [ -f /etc/vagrant-box/egress-restrict.state.resolv.conf.was_symlink ]; then
    ln -sf "$(cat /etc/vagrant-box/egress-restrict.state.resolv.conf.was_symlink)" /etc/resolv.conf
  elif [ -f /etc/vagrant-box/egress-restrict.state.resolv.conf.orig ]; then
    cp -a /etc/vagrant-box/egress-restrict.state.resolv.conf.orig /etc/resolv.conf
  fi
  rm -f /etc/vagrant-box/egress-restrict.state /etc/vagrant-box/egress-restrict.state.resolv.conf.orig /etc/vagrant-box/egress-restrict.state.resolv.conf.was_symlink
  echo "  -> egress restriction reverted"
fi

if command -v apt-get >/dev/null 2>&1; then
  apt-get autoremove -y
  apt-get clean
  rm -rf /var/lib/apt/lists/*
elif command -v dnf >/dev/null 2>&1; then
  dnf -y autoremove || true
  dnf clean all
  rm -rf /var/cache/dnf/*
fi

find /var/log -type f -name "*.log" -exec truncate -s 0 {} \;
find /var/log -type f -name "*.gz" -delete
find /var/log -type f -name "*.1" -delete

unset HISTFILE
rm -f /root/.bash_history
rm -f /home/*/.bash_history

# The Packer-only lease bridge restores the installer address so the build can
# keep its SSH connection after the target receives a new DHCP address. Stop
# and remove its persistent pieces, but do not delete the live secondary IP:
# Packer still needs it until the guest shuts down.
systemctl disable --now kube-ready-packer-lease-bridge.service 2>/dev/null || true
rm -f /etc/systemd/system/kube-ready-packer-lease-bridge.service
rm -f /etc/kube-ready/packer-installer-ip.env
systemctl daemon-reload

# Host keys are generated uniquely by the first-boot identity service.
echo "Removing SSH host keys from the image; first boot regenerates them..."
rm -f /etc/ssh/ssh_host_*

# A released image must not carry a source machine identity.
echo "Clearing machine identity..."
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id

# Remove transient identity evidence generated during the build.
rm -f /etc/vagrant-box/identity-attestation.json

# Optional production/hardened profile marker. Vagrant development images keep
# their insecure public key for Vagrant transport; production promotion should
# create /etc/kube-ready/hardened-ssh and provision an explicit operator key.
if [ "${KUBE_READY_HARDENED_SSH:-0}" = "1" ]; then
  mkdir -p /etc/kube-ready
  touch /etc/kube-ready/hardened-ssh
  rm -f /home/vagrant/.ssh/authorized_keys
fi

# D5: 16 GiB 루트의 빈 공간만 채운다. 임시 호스트 사용량은 늘지만 압축은 쉬워진다.
# 실패 시 오류를 노출하고 파일을 지운 뒤 재빌드할 수 있다.
DD_ERR=$(mktemp /run/kube-ready-zero-fill.XXXXXX)
if LC_ALL=C dd if=/dev/zero of=/EMPTY bs=1M 2>"$DD_ERR"; then
  echo "Zero fill reached end of input unexpectedly" >&2
  rm -f /EMPTY "$DD_ERR"
  exit 1
# GNU dd 는 "dd: error writing '/EMPTY': No space left on device", 26.04 의
# uutils dd 는 "dd: IO error: No space left on device" 를 낸다. 문장 전체가 아니라
# ENOSPC 문구로만 판정한다(정확 일치였을 때 26.04 빌드가 정상 ENOSPC 에서 실패했다).
elif ! grep -Fq "No space left on device" "$DD_ERR"; then
  cat "$DD_ERR" >&2
  rm -f /EMPTY "$DD_ERR"
  exit 1
fi
BYTES=$(stat -c %s /EMPTY)
echo "Zero-filled $BYTES bytes"
rm -f /EMPTY "$DD_ERR"
sync

echo "=== Cleanup Complete ==="
