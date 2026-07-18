# K8s 설치 후 권장 설정

> **참고**: 이 문서는 `dasomel/ubuntu-24.04` / `dasomel/ubuntu-26.04` Box에 K8s를 설치한 후 적용하는 권장 설정입니다.
> Box 자체에는 포함되지 않으며, K8s 설치 후 필요에 따라 적용합니다.

## 0. cgroup v2 (필수 전제)

> [K8s cgroup v2 문서](https://kubernetes.io/docs/concepts/architecture/cgroups/) 참고.
> kubelet과 컨테이너 런타임의 cgroup 드라이버가 일치하지 않으면 kubelet이 기동 실패합니다.

### 버전별 cgroup 상황

| Box | cgroup | 비고 |
|-----|--------|------|
| Ubuntu 24.04 | v2 unified (기본) | v1 잔존하나 기본 비활성 |
| **Ubuntu 26.04** | **v2 전용** | systemd 259에서 **cgroup v1 완전 제거** → v1 워크로드 동작 불가 |

26.04는 cgroup v1을 지원하지 않으므로, v1을 강제하던 구형 런타임/설정은 동작하지 않습니다.
또한 26.04는 강화된 cgroup 마운트 옵션(`nsdelegate`, `memory_recursiveprot`, `memory_hugetlb_accounting`)을 기본 제공합니다.

### 확인

```bash
# cgroup2fs 여야 함 (cgroup v2 unified)
stat -fc %T /sys/fs/cgroup
# 출력: cgroup2fs

# v2 컨트롤러 확인
cat /sys/fs/cgroup/cgroup.controllers
```

### systemd cgroup 드라이버 정렬 (필수)

cgroup v2에서는 **kubelet과 containerd 모두 `systemd` 드라이버**를 사용해야 합니다.

```bash
# containerd: SystemdCgroup = true (아래 1. containerd 섹션에서 설정)
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
```

```yaml
# kubelet: /var/lib/kubelet/config.yaml (또는 kubeadm KubeletConfiguration)
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
```

> kubeadm v1.22+ 는 `cgroupDriver` 미지정 시 `systemd`를 기본값으로 사용합니다. 명시 권장.

### 드라이버 불일치 진단

```bash
# kubelet이 cgroup 드라이버 불일치로 기동 실패할 때
journalctl -u kubelet -n 50 --no-pager | grep -i cgroup
# containerd 현재 드라이버 확인
sudo containerd config dump | grep -i SystemdCgroup
```

---

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

## 7. 노드 운영 주의사항

> Box 프로비저닝 시 K8s 운영을 위해 제거/제외/사전 구성된 항목과 그 이유입니다.

### unattended-upgrades

Box에서 **제거됨** (`apt-get purge`). 재설치하거나 활성화할 경우, 이 패키지가 설치하는
logind drop-in 설정(`InhibitDelayMaxSec=30`)이 kubelet의
[Graceful Node Shutdown](https://kubernetes.io/docs/concepts/architecture/nodes/#graceful-node-shutdown)
(`shutdownGracePeriod` 가 30초를 초과하는 설정)을 깨뜨릴 수 있습니다
([kubernetes/kubernetes#102818](https://github.com/kubernetes/kubernetes/issues/102818)).

재활성화가 필요하다면 반드시 아래와 같이 drop-in을 재정의하세요:

```bash
# /etc/systemd/logind.conf.d/99-k8s-override.conf
sudo mkdir -p /etc/systemd/logind.conf.d
cat <<EOF | sudo tee /etc/systemd/logind.conf.d/99-k8s-override.conf
[Login]
InhibitDelayMaxSec=90
EOF
sudo systemctl restart systemd-logind
```

### ufw / firewalld

**활성화 금지.** Calico 등 CNI가 관리하는 iptables 규칙과 충돌하여 Pod 간 통신 및
NetworkPolicy가 정상 동작하지 않을 수 있습니다 (Tigera 공식 요구사항). 노드 방화벽이
필요하면 CNI가 관리하지 않는 범위에서 raw iptables/nftables 규칙으로 직접 구성하세요.

### crictl 등 CRI 도구

Box에는 **포함되지 않음**. `crictl`(cri-tools)은 K8s 마이너 버전과 정확히 일치하는
버전을 설치해야 하므로, 설치할 K8s 버전이 확정된 이후 사용자가 직접 설치합니다.

```bash
# 예: K8s v1.31 사용 시
VERSION="v1.31.0"
ARCH=$(dpkg --print-architecture)   # amd64 / arm64
curl -LO "https://github.com/kubernetes-sigs/cri-tools/releases/download/${VERSION}/crictl-${VERSION}-linux-${ARCH}.tar.gz"
sudo tar zxvf "crictl-${VERSION}-linux-${ARCH}.tar.gz" -C /usr/local/bin
```

### Longhorn 스토리지

Longhorn(V1 엔진) CSI 전제조건은 Box에 **사전 구성되어 있습니다**:
`open-iscsi`, `iscsi_tcp` 커널 모듈(자동 로드 + `iscsid` 활성화), `nfs-common`, `cryptsetup`/`dmsetup`
(볼륨 암호화/LUKS2 및 V2 엔진용). 별도 노드 준비 없이 Longhorn 설치를 진행할 수 있습니다.

### 시간 동기화 (chrony)

Box는 **chrony + 한국 NTP 서버**(time.bora.net, time.kriss.re.kr, ntp.kornet.net, ntp.ubuntu.com)로
사전 구성되어 있습니다. Ubuntu 26.04부터 chrony가 OS 기본 NTP 데몬이며, etcd는 노드 간 clock skew에
민감하므로 chrony 사용이 권장됩니다. 상태 확인:

```bash
chronyc sources -v
```

### multipath-tools

Box에는 **미설치**되어 있습니다. `multipathd`가 Longhorn 볼륨을 가로채 mount 실패를 유발할 수 있습니다
([Longhorn KB](https://longhorn.io/kb/troubleshooting-volume-mount-problems/)). multipath가 꼭
필요한 환경이라면 설치 후 `/etc/multipath.conf`에 blacklist를 추가하세요:

```
blacklist {
    devnode "^sd[a-z0-9]+"
}
```

### OpenEBS 사용 시

Box에는 **포함되지 않은** 전제조건입니다. 사용하는 스토리지 엔진에 따라 직접 설치가 필요합니다:

- LocalPV-LVM: `lvm2`
- Mayastor(Replicated Storage): `nvme-cli`, `nvme-tcp`/`nvme-fabrics` 커널 모듈, HugePages 2GiB(2MiB x 1024)

특정 스택 전용 요구사항이라 Box에는 포함되지 않았습니다.

### auditd

Box에 **설치되어 있으나 기본 비활성화** 상태입니다 (관리형 K8s 노드 이미지 관행). CIS 벤치마크 대응이
필요하면 아래로 활성화하세요:

```bash
sudo systemctl enable --now auditd
```

I/O 제한 설정(`max_log_file=50`, `max_log_file_action=ROTATE`, `disk_full_action=SUSPEND`)이
사전 적용되어 있습니다.

---

## 참고 자료

- [Kubernetes 공식 문서](https://kubernetes.io/docs/)
- [containerd 공식 문서](https://containerd.io/)
- [kubeadm 설치 가이드](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [Cilium 문서](https://docs.cilium.io/)
- [K8s sysctl 설정](https://kubernetes.io/docs/tasks/administer-cluster/sysctl-cluster/)
