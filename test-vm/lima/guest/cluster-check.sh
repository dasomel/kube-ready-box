#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
#
# 게스트 안에서 일반 사용자로 실행(kubeadm init 이후): Flannel, 노드 Ready,
# CoreDNS, 테스트 파드와 Service 이름 해석/라우팅을 확인한다.
set -euo pipefail

FLANNEL_VERSION="${FLANNEL_VERSION:-v0.28.10}"

mkdir -p "$HOME/.kube"
sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

kubectl apply -f "https://github.com/flannel-io/flannel/releases/download/${FLANNEL_VERSION}/kube-flannel.yml" >/dev/null
kubectl taint nodes --all node-role.kubernetes.io/control-plane- >/dev/null 2>&1 || true
kubectl wait --for=condition=Ready node --all --timeout=300s
kubectl -n kube-system wait --for=condition=Ready pod -l k8s-app=kube-dns --timeout=300s

kubectl run nginx --image=nginx:1.27-alpine --port=80 >/dev/null
kubectl expose pod nginx --port=80 >/dev/null
kubectl wait --for=condition=Ready pod/nginx --timeout=300s
# Service 이름으로 요청해 응답을 받으면 클러스터 DNS 와 kube-proxy 경로가 모두 동작한 것이다.
kubectl run probe --image=busybox:1.36 --restart=Never --command -- \
  sh -c 'wget -qO- -T5 http://nginx.default.svc.cluster.local | grep -o "<title>.*</title>"' >/dev/null
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/probe --timeout=180s
kubectl logs probe | grep -q 'Welcome to nginx' || { echo "service probe failed" >&2; kubectl logs probe >&2; exit 1; }
echo "service_probe PASS"
kubectl delete pod probe --wait=false >/dev/null

kubectl get nodes -o wide
kubectl get pods -A --no-headers | awk '{print $1, $2, $3, $4}'
