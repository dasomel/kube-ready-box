# NixOS Kubernetes-Ready Vagrant Box

이 디렉터리는 선언적(Declarative) 불변 Linux인 **NixOS**를 기반으로 Kubernetes 최적화 설정이 적용된 Vagrant Box를 빌드하고 테스트하는 환경을 제공합니다.

---

## 💡 구성 특징

- **선언적 튜닝 (`configuration.nix`)**: `02-os-tuning.sh` 및 `04-k8s-prereq.sh`와 동일한 K8s 커널 파라미터(`sysctl`), 소켓 버퍼, memory limits, inotify, ARP/conntrack 설정 적용
- **스왑 비활성화**: K8s 노드 필수 요구사항 반영
- **네트워크 모듈 사전 로드**: `overlay`, `br_netfilter`, `iscsi_tcp`
- **CSI 사전 구성**: Longhorn 등 CSI 스토리지를 위한 `openiscsi` 데몬 및 영구 eBPF 마운트(`/sys/fs/bpf`) 지원
- **런타임 및 CLI 도구 탑재**: `containerd`, `docker`, `kubectl`, `helm`, `cri-tools`, `ipvsadm`, `socat` 등 사전 내장
- **Vagrant 호환성**: Vagrant 보안 SSH 키 및 패스워드 없는 sudo 권한 자동 부여

---

## 🛠️ 빌드 방법 (`build.sh`)

Nix 패키지 관리자가 설치된 환경에서 `nixos-generators`를 사용하여 수 분 내로 `.box` 파일을 생성합니다.

```bash
# 1. VirtualBox용 Vagrant Box 빌드
./nixos/build.sh virtualbox

# 2. QEMU / libvirt용 Vagrant Box 빌드
./nixos/build.sh qemu
```

빌드가 완료되면 `.box` 파일이 `nixos/output-vagrant/` 및 `nixos/dist/` 디렉터리에 자동으로 대피 보관됩니다.

---

## 🚀 사용 및 검증방법

```bash
# 로컬 Box 추가
vagrant box add dasomel/nixos-kube-ready nixos/dist/dasomel-nixos-kube-ready-$(uname -m)-vagrant-virtualbox.box

# Vagrant 가동
cd nixos
vagrant up
vagrant ssh
```

가동된 VM 내부에서 다음을 통해 K8s 튜닝 적용 상태를 검증할 수 있습니다:

```bash
# containerd 런타임 확인
systemctl status containerd

# K8s 커널 모듈 확인
lsmod | grep -E 'overlay|br_netfilter|iscsi_tcp'

# sysctl 튜닝 값 확인
sysctl net.bridge.bridge-nf-call-iptables vm.max_map_count net.core.somaxconn
```
