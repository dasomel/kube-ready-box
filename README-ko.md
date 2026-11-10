[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Build AMD64](https://github.com/dasomel/kube-ready-box/actions/workflows/build-amd64.yml/badge.svg)](https://github.com/dasomel/kube-ready-box/actions/workflows/build-amd64.yml)
[![Box - 24.04 ext4](https://img.shields.io/badge/Vagrant-24.04--ext4-blue)](https://dasomel.github.io/kube-ready-box/boxes/ubuntu-24.04-ext4.json)
[![Box - 24.04 xfs](https://img.shields.io/badge/Vagrant-24.04--xfs-green)](https://dasomel.github.io/kube-ready-box/boxes/ubuntu-24.04-xfs.json)
[![Box - 26.04 ext4](https://img.shields.io/badge/Vagrant-26.04--ext4-blue)](https://dasomel.github.io/kube-ready-box/boxes/ubuntu-26.04-ext4.json)
[![Box - 26.04 xfs](https://img.shields.io/badge/Vagrant-26.04--xfs-green)](https://dasomel.github.io/kube-ready-box/boxes/ubuntu-26.04-xfs.json)

**Languages**: [English](README.md) | [한국어](README-ko.md)

OS 수준 최적화가 적용된 Kubernetes-ready Ubuntu Vagrant Box. **24.04 LTS** (Noble Numbat, 기본값)과 **26.04 LTS** (Resolute Raccoon, 커널 Linux 7.0) 지원.

> **배포 경로 변경 (v0.3.0+)**: HCP Vagrant(구 Vagrant Cloud)가 종료됩니다. 2026-10-01부터 신규 업로드가 막혔고, 2026-12-31 이후 `dasomel/*`를 포함한 모든 호스팅 박스가 삭제됩니다. 박스는 이제 GitHub Release 자산으로, Vagrant 카탈로그는 GitHub Pages로 제공합니다. [Box 배포](docs/box-distribution.md) 참고.
>
> | Box | 버전 | Provider (아키텍처) |
> |---|---|---|
> | `dasomel/ubuntu-24.04-ext4`, `dasomel/ubuntu-24.04-xfs` | 0.3.3 | `vmware_desktop` (arm64), `virtualbox` (amd64) |
> | `dasomel/ubuntu-26.04-ext4`, `dasomel/ubuntu-26.04-xfs` | 0.3.3 | `vmware_desktop` (arm64), `virtualbox` (amd64) |
> | `dasomel/rocky-9-ext4`, `dasomel/rocky-9-xfs` | 0.1.3 | `vmware_desktop` (arm64) |
> | `dasomel/nixos-kube-ready` | 0.2.2 | `libvirt` (arm64, `vagrant-qemu` 가능) |
>
> Ubuntu amd64 박스는 VirtualBox용만 있습니다. GitHub의 x86 러너에서 빌드하고 부팅까지 검증하는데, 그 러너에서는 VirtualBox는 돌지만 VMware는 돌릴 수 없습니다. VirtualBox arm64 박스(arm64 빌드 호스트에서 VirtualBox SSH를 검증할 수 없음)와 Rocky/NixOS amd64 박스는 없습니다.
>
> **Ubuntu 버전 재정렬**: Ubuntu 박스는 Vagrant Cloud 1.1.0 다음 버전이 **0.3.x**입니다(1.1.0은 GitHub Release 자산이 아니었고 Vagrant Cloud와 함께 삭제됩니다). Vagrant는 1.1.0을 0.3.x보다 높게 보므로 기존 버전을 먼저 지우세요: `vagrant box remove dasomel/<box> --box-version 1.1.0`.

## 24.04 vs 26.04

| | 24.04 LTS (Noble Numbat) | 26.04 LTS (Resolute Raccoon) |
|---|---|---|
| 커널 | 6.8 | **7.0** |
| init / cgroup | systemd 255, cgroup v2 기본 | systemd 259, **cgroup v1 제거 (v2 전용)** |
| 컨테이너 런타임 | containerd 1.7 | containerd 2.2 / runc 1.4 |
| 암호화 | TLS 1.2+ | **양자내성(PQC) 기본** (OpenSSL 3.5 / OpenSSH 10.2) |
| 핵심 유틸 | GNU coreutils, sudo | 일부 Rust 재작성 (uutils, sudo-rs) |
| 선택 기준 | 최대 안정성 (**기본값**) | 최신 LTS, 커널 7.0 기능 |

> **K8s 참고**: 26.04는 cgroup v2 전용 — kubelet/containerd에 `SystemdCgroup=true` 필요([K8s 설치 후 설정](docs/k8s-post-install.md)). 두 라인 모두 동일하게 K8s 튜닝됨. 상세 비교: [마이그레이션 노트](docs/ubuntu-2604-migration/24-04-vs-26-04-comparison.md).

## 주요 기능

- **기본 OS**: Ubuntu 24.04 LTS 또는 26.04 LTS Cloud Image
- **멀티 아키텍처**: AMD64, ARM64
- **멀티 프로바이더**: VirtualBox, VMware Fusion
- **파일시스템 선택**: ext4 (기본) 또는 xfs
- **K8s 준비 완료**: Kubernetes를 위한 OS 튜닝 (K8s는 미포함)
- **1TB 디스크**: 가상 디스크는 1,000,000 MB로 thin provisioning, 루트는 첫 부팅 시 ~975 GiB까지 확장. `.box` 다운로드 크기는 0.97-1.97 GiB (아래 참고)
- **자동 확장**: 이미지의 루트 LV는 16 GiB이며 첫 부팅 시 디스크 전체로 확장 (`kube-ready-growroot.service`, 증적은 `/etc/vagrant-box/growroot.json`). `/swap.img`는 제거됨

> **NixOS 변형**: 선언적 NixOS 박스를 `dasomel/nixos-kube-ready`(0.2.2, libvirt `.box` 0.97 GiB)로 별도 배포합니다 (libvirt / arm64 — Apple Silicon에서는 `vagrant-qemu`로 동일 박스 사용). [`nixos/`](nixos/) 참고.

### 빌드 매트릭스

| 프로바이더 | AMD64 | ARM64 | 비고 |
|----------|-------|-------|-------|
| VirtualBox | ✅ | ✅ | ARM64는 VirtualBox 7.1+ 필요 |
| VMware Fusion | ✅* | ✅ | Apple Silicon 지원; *AMD64는 로컬 빌드 전용 — 릴리스는 ARM64만 제공 (빌드 호스트 제약) |

## 빠른 시작

### 설치

Box는 카탈로그 URL로 제공됩니다 (Vagrant는 `application/json`을 반환하는 HTTP URL만 카탈로그로 취급하며 GitHub Pages가 이를 만족). 체크섬이 검증되고 `vagrant box outdated`, `vagrant box update`가 동작합니다.

```bash
# 24.04 ext4 (기본, 안정, 범용)
vagrant init dasomel/ubuntu-24.04-ext4 \
  https://dasomel.github.io/kube-ready-box/boxes/ubuntu-24.04-ext4.json
vagrant up --provider=vmware_desktop

# 또는 Box를 직접 추가
vagrant box add https://dasomel.github.io/kube-ready-box/boxes/ubuntu-24.04-xfs.json
```

카탈로그 URL 형식: `https://dasomel.github.io/kube-ready-box/boxes/<box-name>.json` (`ubuntu-24.04-ext4`, `ubuntu-24.04-xfs`, `ubuntu-26.04-ext4`, `ubuntu-26.04-xfs`, `rocky-9-ext4`, `rocky-9-xfs`, `nixos-kube-ready`). 자세한 내용: [Box 배포](docs/box-distribution.md).

### 파일시스템 비교

| | ext4 | xfs |
|---|---|---|
| **적합한 용도** | 범용 | K8s 워크로드, 대용량 파일 |
| **K8s Quota** | 미지원 | `--local-storage-capacity-isolation` |
| **온라인 축소** | 지원 | 미지원 |
| **Box 크기 (`.box`, arm64; Ubuntu 0.3.3, Rocky 0.1.3)** | 24.04: 1.45 GiB, 26.04: 1.76 GiB, Rocky 9: 1.77 GiB | 24.04: 1.55 GiB, 26.04: 1.97 GiB, Rocky 9: 1.92 GiB |

### Vagrantfile 예제

```ruby
Vagrant.configure("2") do |config|
  # 24.04: "dasomel/ubuntu-24.04-ext4" 또는 "dasomel/ubuntu-24.04-xfs"
  # 26.04: "dasomel/ubuntu-26.04-ext4" 또는 "dasomel/ubuntu-26.04-xfs"
  config.vm.box = "dasomel/ubuntu-24.04-ext4"
  config.vm.box_url = "https://dasomel.github.io/kube-ready-box/boxes/ubuntu-24.04-ext4.json"

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

### 사전 설치된 도구

| 분류 | 도구 |
|------|------|
| **K8s 에코시스템** | jq, yq, bash-completion, nfs-common, sshpass |
| **모니터링** | sysstat, iotop, iftop, nload, nethogs, dool |
| **네트워크 진단** | ipvsadm, ipset, conntrack, ethtool, tcpdump, nmap |
| **성능 분석** | linux-tools, bpfcc-tools, bpftrace |

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

- [아키텍처](docs/architecture.md) - 빌드 파이프라인, 산출물 매트릭스, 런타임 경계 및 불변 조건
- [Box 사용 가이드](docs/usage.md) - 상세 사용 방법
- [K8s 설치 후 설정](docs/k8s-post-install.md) - containerd/kubelet 튜닝
- [Packer 빌드 가이드](packer/README.md) - 소스에서 Box 빌드하기
- [Box 배포](docs/box-distribution.md) - GitHub Release 자산, Pages 카탈로그, 게시 절차, HCP Vagrant 종료 일정
- [Vagrant Cloud 가이드](docs/VAGRANT_CLOUD.md) - 폐기됨 (이력용)
- [HCP 자격증명 설정](docs/hcp-credentials.md) - 폐기됨 (Vagrant Cloud 게시용)
- [배포 체크리스트](docs/DEPLOY_CHECKLIST.md) - 릴리스 전 검증
- [법적 고지 및 라이선스](docs/legal.md) - OSS 라이선스 및 컴플라이언스
- [변경 이력](CHANGELOG.md) - 릴리즈 노트 및 버전 히스토리

## 소스에서 빌드하기

```bash
cd packer

# Packer 플러그인 초기화
./build.sh init

# 24.04 빌드 (기본값)
./build.sh vmware-arm64
./build.sh vmware-arm64 --fs=xfs

# 26.04 빌드
./build.sh vmware-arm64 --version=26.04
./build.sh vmware-arm64 --version=26.04 --fs=xfs

# 전체 빌드
./build.sh all                         # 24.04 ext4
./build.sh all --version=26.04         # 26.04 ext4
```

> **게시**: `upload-boxes.sh`는 Vagrant Cloud용이며 폐기되었습니다. GitHub Release 자산 + Pages 카탈로그로 게시하세요: [Box 배포](docs/box-distribution.md#publishing-maintainers).

> **CI**: GitHub Actions `workflow_dispatch`의 `ubuntu_version` input으로 24.04 또는 26.04를 선택할 수 있습니다.

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
| Ubuntu 24.04 / 26.04 | [Various](https://ubuntu.com/legal/open-source-licences) |
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

- [Releases (Box 다운로드)](https://github.com/dasomel/kube-ready-box/releases)
- [Box 카탈로그 (GitHub Pages)](https://dasomel.github.io/kube-ready-box/boxes/ubuntu-24.04-ext4.json)
- [GitHub Repository](https://github.com/dasomel/kube-ready-box)
- [Issue Tracker](https://github.com/dasomel/kube-ready-box/issues)
