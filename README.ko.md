# kube-ready-box

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Vagrant Cloud](https://img.shields.io/badge/Vagrant-Cloud-blue)](https://app.vagrantup.com/dasomel/boxes/ubuntu-24.04)

**Languages**: [English](README.md) | [한국어](README.ko.md)

OS 수준 최적화가 적용된 Kubernetes-ready Ubuntu 24.04 LTS Vagrant Box

> **Vagrant Cloud**: `dasomel/ubuntu-24.04`

## 주요 기능

- **기본 OS**: Ubuntu 24.04 LTS Cloud Image
- **멀티 아키텍처**: AMD64, ARM64
- **멀티 프로바이더**: VirtualBox, VMware Fusion
- **K8s 준비 완료**: Kubernetes를 위한 OS 튜닝 (K8s는 미포함)

### 빌드 매트릭스

| 프로바이더 | AMD64 | ARM64 | 비고 |
|----------|-------|-------|-------|
| VirtualBox | ✅ | ✅ | ARM64는 VirtualBox 7.1+ 필요 |
| VMware Fusion | ✅ | ✅ | Apple Silicon 지원 |

## 빠른 시작

### 설치

```bash
# VirtualBox (아키텍처 자동 감지)
vagrant init dasomel/ubuntu-24.04
vagrant up

# VMware Fusion
vagrant init dasomel/ubuntu-24.04
vagrant up --provider=vmware_desktop
```

### Vagrantfile 예제

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "dasomel/ubuntu-24.04"

  config.vm.provider "virtualbox" do |vb|
    vb.memory = 4096
    vb.cpus = 2
  end

  config.vm.provider "vmware_desktop" do |v|
    v.vmx["memsize"] = "4096"
    v.vmx["numvcpus"] = "2"
  end

  config.vm.hostname = "k8s-node"
  config.vm.network "private_network", ip: "192.168.56.10"
end
```

## 포함된 내용

### OS 최적화

- **커널 파라미터**: 네트워크, 메모리, 파일시스템 튜닝
- **리소스 제한**: 파일 디스크립터, 프로세스, 메모리 락
- **K8s 필수 요구사항**: Swap 비활성화, 커널 모듈, IP 포워딩
- **디스크 I/O**: 스케줄러 및 read-ahead 최적화
- **네트워크**: TCP 버퍼, conntrack, 링 버퍼

### 포함되지 않은 내용

사용자가 요구사항에 따라 직접 설치하는 컴포넌트:

- 컨테이너 런타임 (containerd, CRI-O)
- Kubernetes (kubeadm, kubelet, kubectl)
- CNI 플러그인 (Flannel, Calico, Cilium)

## K8s 설치 (Box 설정 후)

```bash
# 1. containerd 설치
sudo apt-get update && sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd && sudo systemctl enable containerd

# 2. K8s 설치 (원하는 버전 선택)
K8S_VERSION="v1.31"
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key" | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update && sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# 3. 클러스터 초기화 (마스터 노드)
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
```

## Box 튜닝 확인

```bash
# 튜닝 설정 확인
vagrant ssh -c "cat /etc/vagrant-box/info.json"
vagrant ssh -c "/bin/bash /etc/vagrant-box/check-tuning.sh"
```

## 문서

- [Box 사용 가이드](usage.md) - 상세 사용 방법
- [K8s 설치 후 설정](k8s-post-install.md) - containerd/kubelet 튜닝
- [Packer 빌드 가이드](packer/README.md) - 소스에서 Box 빌드하기
- [Vagrant Cloud 가이드](VAGRANT_CLOUD.md) - Box 업로드, 관리, 삭제 방법
- [법적 고지 및 라이선스](legal.md) - OSS 라이선스 및 컴플라이언스
- [변경 이력](CHANGELOG.md) - 릴리즈 노트 및 버전 히스토리

## 소스에서 빌드하기

```bash
cd packer

# Packer 플러그인 초기화
./build.sh init

# 특정 Box 빌드
./build.sh vmware-arm64      # VMware ARM64
./build.sh virtualbox-arm64  # VirtualBox ARM64

# 모든 Box 빌드 (4개)
./build.sh all
```

## 요구사항

### Box 사용 시

- Vagrant 2.3+
- VirtualBox 7.1+ (ARM64용) 또는 VMware Fusion

### 소스 빌드 시

- Packer 1.8+
- VirtualBox 7.1+ / VMware Fusion
- Box당 20GB+ 디스크 공간

## 라이선스

이 프로젝트는 MIT License로 배포됩니다. 자세한 내용은 [LICENSE](LICENSE) 파일을 참조하세요.

### 서드파티 라이선스

이 Box에는 다양한 오픈소스 프로젝트의 소프트웨어가 포함되어 있습니다. 자세한 내용은 [NOTICE](NOTICE)를 참조하세요.

| 컴포넌트 | 라이선스 |
|-----------|---------|
| Ubuntu 24.04 | [Various](https://ubuntu.com/legal/open-source-licences) |
| Kubernetes | Apache 2.0 |
| containerd | Apache 2.0 |

## AI 보조 개발

이 프로젝트는 AI 코딩 어시스턴트를 위한 컨텍스트 파일을 `.agent/` 디렉토리에 포함하고 있습니다:

- **[AGENT.md](.agent/AGENT.md)** - 완전한 기술 가이드 (Packer, K8s 튜닝, 최적화)
- **[SECURITY.md](.agent/SECURITY.md)** - 보안 가이드라인 및 모범 사례
- **[skills/](.agent/skills/)** - 자동화된 리뷰를 위한 AI 에이전트 스킬

[Claude Code](https://claude.ai/claude-code) 같은 도구를 위해 설계되었지만, Packer, Kubernetes, Ubuntu 최적화 작업을 하는 모든 개발자에게 유용한 기술 문서입니다.

## 기여하기

기여는 언제나 환영합니다! Pull Request를 자유롭게 제출해 주세요.

## 링크

- [Vagrant Cloud](https://app.vagrantup.com/dasomel/boxes/ubuntu-24.04)
- [GitHub Repository](https://github.com/dasomel/kube-ready-box)
- [Issue Tracker](https://github.com/dasomel/kube-ready-box/issues)
