#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
#
# 게스트 안에서 root 로 실행: containerd(Ubuntu 패키지) + kubeadm/kubelet/kubectl.
# 박스는 런타임을 일부러 넣지 않으므로(packer/scripts/04-k8s-prereq.sh) 이 단계가
# STRICT_RUNTIME=1 preflight 와 kubeadm init 의 전제가 된다.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

K8S_MINOR="${K8S_MINOR:-v1.37}"   # 2026-11-08 PoC: v1.37.2

apt-get update -qq
apt-get install -y -qq containerd ca-certificates curl gpg >/dev/null
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
grep -q 'SystemdCgroup = true' /etc/containerd/config.toml || { echo "SystemdCgroup not enabled" >&2; exit 1; }
systemctl restart containerd
systemctl enable containerd >/dev/null

install -d -m 0755 /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" \
  | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list
apt-get update -qq
apt-get install -y -qq kubelet kubeadm kubectl >/dev/null
apt-mark hold kubelet kubeadm kubectl >/dev/null
systemctl enable kubelet >/dev/null
containerd --version
kubeadm version -o short
