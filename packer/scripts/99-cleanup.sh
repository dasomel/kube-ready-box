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

apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*

find /var/log -type f -name "*.log" -exec truncate -s 0 {} \;
find /var/log -type f -name "*.gz" -delete
find /var/log -type f -name "*.1" -delete

unset HISTFILE
rm -f /root/.bash_history
rm -f /home/*/.bash_history

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

dd if=/dev/zero of=/EMPTY bs=1M 2>/dev/null || true
rm -f /EMPTY
sync

echo "=== Cleanup Complete ==="
