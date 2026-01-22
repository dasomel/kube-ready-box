# K8s 설치 후 권장 설정

> **참고**: 이 문서는 `dasomel/ubuntu-24.04` Box에 K8s를 설치한 후 적용하는 권장 설정입니다.
> Box 자체에는 포함되지 않으며, K8s 설치 후 필요에 따라 적용합니다.

## 1. containerd 최적화

> [containerd 공식 문서](https://containerd.io/), [K8s 컨테이너 런타임](https://kubernetes.io/docs/setup/production-environment/container-runtimes/) 참고.

### containerd vs Docker 성능 비교

| 항목 | containerd | Docker | 비고 |
|------|------------|--------|------|
| 컨테이너 시작 시간 | ~87ms | ~151ms | containerd 42% 빠름 |
| 메모리 사용량 | 낮음 | 높음 | Docker 데몬 오버헤드 없음 |
| K8s 통합 | 직접 연결 | dockershim 필요 (deprecated) | 15-20% 성능 향상 |
| 프로덕션 점유율 | 52-70% | 개발환경 68% | 2024-2025 기준 |

### containerd 설치

```bash
# containerd 설치
sudo apt-get update
sudo apt-get install -y containerd

# 기본 설정 생성
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

# systemd cgroup 드라이버 활성화 (K8s 필수)
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# 서비스 재시작
sudo systemctl restart containerd
sudo systemctl enable containerd
```

### 권장 config.toml

```toml
# /etc/containerd/config.toml
version = 2

[plugins."io.containerd.grpc.v1.cri"]
  # 샌드박스 이미지 (K8s 버전에 맞춰 업데이트)
  sandbox_image = "registry.k8s.io/pause:3.10"

  # 이미지 풀 타임아웃 (대용량 이미지용)
  image_pull_progress_timeout = "5m"

[plugins."io.containerd.grpc.v1.cri".containerd]
  # 스냅샷터 (기본 overlayfs, 최소 커널 4.x 필요)
  snapshotter = "overlayfs"
  default_runtime_name = "runc"

  # 이미지 풀 동시성 (기본 3 → 병렬 풀링)
  max_concurrent_downloads = 10

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
  runtime_type = "io.containerd.runc.v2"

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
  # systemd cgroup 드라이버 (K8s 권장)
  SystemdCgroup = true

[plugins."io.containerd.grpc.v1.cri".cni]
  bin_dir = "/opt/cni/bin"
  conf_dir = "/etc/cni/net.d"

# 가비지 컬렉션 설정
[plugins."io.containerd.gc.v1.scheduler"]
  pause_threshold = 0.02
  deletion_threshold = 0
  mutation_threshold = 100
  schedule_delay = "0s"
  startup_delay = "100ms"

# 메트릭 (모니터링용)
[metrics]
  address = "127.0.0.1:1338"
  grpc_histogram = true
```

### containerd 서비스 리소스 제한

```bash
# /etc/systemd/system/containerd.service.d/limits.conf
sudo mkdir -p /etc/systemd/system/containerd.service.d
cat <<EOF | sudo tee /etc/systemd/system/containerd.service.d/limits.conf
[Service]
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
EOF

sudo systemctl daemon-reload
sudo systemctl restart containerd
```

### containerd 2.0 신규 기능

| 기능 | 설명 |
|------|------|
| User Namespaces | 컨테이너 내 root → 호스트 비특권 UID 매핑 (보안 강화) |
| Sandbox API | 샌드박스 관리 개선 |
| Transfer Service | 이미지 전송 최적화 |
| NRI (Node Resource Interface) | 플러그인 방식 리소스 관리 |

---

## 2. kubelet 튜닝

### kubelet 설치

```bash
# K8s 저장소 추가 (원하는 버전 선택)
K8S_VERSION="v1.31"  # 또는 v1.30, v1.29 등
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key" | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

# kubeadm, kubelet, kubectl 설치
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable kubelet
```

### 권장 KubeletConfiguration

```yaml
# /var/lib/kubelet/config.yaml 또는 kubeadm 설정

apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration

# 리소스 예약
kubeReserved:
  cpu: "500m"
  memory: "512Mi"
  ephemeral-storage: "1Gi"
systemReserved:
  cpu: "500m"
  memory: "512Mi"
  ephemeral-storage: "1Gi"

# Eviction 설정
evictionHard:
  memory.available: "200Mi"
  nodefs.available: "10%"
  imagefs.available: "15%"
evictionSoft:
  memory.available: "500Mi"
  nodefs.available: "15%"
evictionSoftGracePeriod:
  memory.available: "1m"
  nodefs.available: "1m"

# 이미지 가비지 컬렉션
imageGCHighThresholdPercent: 85
imageGCLowThresholdPercent: 80

# 성능 설정
maxPods: 110
podsPerCore: 0
serializeImagePulls: false
registryPullQPS: 10
registryBurst: 20

# 로깅
containerLogMaxSize: "50Mi"
containerLogMaxFiles: 5
```

### kubeadm 클러스터 초기화 시 적용

```bash
# kubeadm-config.yaml
cat <<EOF > kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: "v1.31.0"
networking:
  podSubnet: "10.244.0.0/16"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
kubeReserved:
  cpu: "500m"
  memory: "512Mi"
systemReserved:
  cpu: "500m"
  memory: "512Mi"
evictionHard:
  memory.available: "200Mi"
  nodefs.available: "10%"
EOF

# 클러스터 초기화
sudo kubeadm init --config kubeadm-config.yaml
```

---

## 3. CNI 설정

### eBPF/Cilium CNI (권장)

> [Cilium](https://cilium.io/)은 eBPF 기반 CNI로 iptables 대비 CPU 오버헤드와 지연시간을 크게 줄입니다.

```bash
# Helm 설치 (없는 경우)
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Cilium 설치
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=${API_SERVER_IP} \
  --set k8sServicePort=6443

# kube-proxy 비활성화 (Cilium이 대체)
kubectl -n kube-system delete ds kube-proxy
kubectl -n kube-system delete cm kube-proxy

# 설치 확인
cilium status
```

### Flannel CNI (간단한 설정)

```bash
# Flannel 설치
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

### Calico CNI (네트워크 정책 필요 시)

```bash
# Calico 설치
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml
```

---

## 4. 노드 역할별 권장 사양

| 역할 | CPU | Memory | Disk | 비고 |
|------|-----|--------|------|------|
| Master (소규모) | 2 | 4GB | 50GB | 노드 10개 이하 |
| Master (중규모) | 4 | 8GB | 100GB | 노드 100개 이하 |
| Master (대규모) | 8 | 16GB | 200GB | 노드 100개 이상 |
| Worker (범용) | 4 | 8GB | 100GB | 일반 워크로드 |
| Worker (고성능) | 8+ | 32GB+ | 500GB+ | 메모리 집약적 |

---

## 5. 권장 도구

### kubectl 설정

```bash
# 자동완성
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'alias k=kubectl' >> ~/.bashrc
echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc

# kube-ps1 (프롬프트에 컨텍스트 표시)
git clone https://github.com/jonmosco/kube-ps1.git ~/.kube-ps1
echo 'source ~/.kube-ps1/kube-ps1.sh' >> ~/.bashrc
echo "PS1='[\u@\h \W \$(kube_ps1)]\$ '" >> ~/.bashrc
```

### 권장 도구 목록

| 도구 | 용도 | 설치 |
|------|------|------|
| Helm | 패키지 관리자 | `curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \| bash` |
| k9s | 클러스터 TUI | `curl -sS https://webinstall.dev/k9s \| bash` |
| stern | 멀티 Pod 로그 | GitHub Releases |
| kubectx/kubens | 컨텍스트/네임스페이스 전환 | `apt install kubectx` |
| kustomize | 설정 관리 | GitHub Releases |
| lens | 클러스터 GUI | https://k8slens.dev/ |

---

## 6. 설정 확인 스크립트

```bash
#!/bin/bash
# check-k8s-setup.sh

echo "=== K8s Setup Check ==="

echo -e "\n[1] containerd 상태"
systemctl is-active containerd
containerd --version

echo -e "\n[2] kubelet 상태"
systemctl is-active kubelet
kubelet --version

echo -e "\n[3] 클러스터 상태"
kubectl cluster-info
kubectl get nodes

echo -e "\n[4] CNI 상태"
kubectl get pods -n kube-system | grep -E "cilium|flannel|calico"

echo -e "\n[5] 시스템 리소스"
kubectl top nodes 2>/dev/null || echo "metrics-server 미설치"

echo -e "\n=== Check Complete ==="
```

---

## 참고 자료

- [Kubernetes 공식 문서](https://kubernetes.io/docs/)
- [containerd 공식 문서](https://containerd.io/)
- [kubeadm 설치 가이드](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [Cilium 문서](https://docs.cilium.io/)
- [K8s sysctl 설정](https://kubernetes.io/docs/tasks/administer-cluster/sysctl-cluster/)
