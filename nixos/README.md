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

## 현재 상태 (2026-08-11)

**`dasomel/nixos-kube-ready` 0.1.1 배포됨** (libvirt / arm64, 공개).
디스크 이미지를 빌드한 뒤 `package-box.sh`로 직접 Vagrant 박스로 포장하는 구조입니다.

| 경로 | 상태 |
|------|------|
| `raw-efi` 이미지 빌드 | ✅ 컨테이너에서 빌드 (아래 KVM 주의사항 참고) |
| libvirt 박스 → `vagrant up --provider qemu` (macOS) | ✅ 부팅·SSH·설정 반영 검증 |
| libvirt 박스 → `vagrant up --provider libvirt` (Linux) | ⚠️ 미검증 (macOS에 libvirt 없음). 박스 형식은 동일 |
| `vmware` 이미지 → `vagrant up --provider vmware_desktop` | ✅ 검증 완료, 다만 배포하지 않음 |

**nixos-generators가 ARM64에서 만들지 못하는 포맷:**

| 포맷 | 결과 |
|------|------|
| `vagrant-virtualbox` | ❌ nixpkgs가 게스트 확장용 `pkgsi686Linux`를 요구 → `i686 Linux package set can only be used with the x86 family` (평가 단계 중단) |
| `vagrant-libvirt` | ❌ 존재하지 않는 포맷 (`nixos-generate --list`로 확인) |
| `qcow-efi` | ❌ `Required features: {kvm}` |

## 🚀 사용

```bash
vagrant init dasomel/nixos-kube-ready
vagrant up --provider qemu       # macOS (Apple Silicon, vagrant-qemu 플러그인)
vagrant up --provider libvirt    # Linux
```

macOS에 별도 박스가 필요 없습니다. vagrant-qemu가 `box_format: "libvirt"`로 선언돼 있어 같은 박스를 씁니다.

---

## 🛠️ 빌드 → 포장 → 배포

박스는 2단계로 만듭니다. nixos-generators는 **디스크 이미지**까지만 만들고, Vagrant 박스 포장은
`package-box.sh`가 담당합니다 (ARM64에서 박스 포맷을 쓸 수 없기 때문 — 위 표 참고).

```bash
# 1. 디스크 이미지 빌드 (Nix 필요. 없으면 아래 도커 경로)
./nixos/build.sh raw                     # raw-efi -> dist/dasomel-...-raw-efi.img

# 2. Vagrant 박스로 포장
./nixos/package-box.sh                   # -> dist/dasomel-...-arm64-libvirt.box
./nixos/package-box.sh -p vmware_desktop # -> dist/dasomel-...-arm64-vmware_desktop.box

# 3. Vagrant Cloud 배포 (검증된 프로바이더만 좁혀서)
PROVIDERS=libvirt VERSION=0.1.1 ./nixos/upload-nixos.sh

# 부가: SBOM(SPDX 2.3 JSON) 생성 — 박스에 내장되지 않고 dist/에 별도 파일로 떨어집니다
./nixos/build.sh sbom
```

파일명 규칙은 `box-common.sh` 한 곳에서만 정의하며 세 스크립트가 공유합니다. 이름을 각자 조립하면
빌드 산출물과 업로드 대상이 어긋나 "업로드 0건인데 성공"으로 보고되는 사고가 납니다.

### Nix가 없는 호스트 (macOS 등)

이 저장소에서 실제로 이미지가 만들어진 유일한 경로입니다. Docker 데몬만 있으면 됩니다.

```bash
docker run --rm -v nixcache:/nix -v "$(pwd)/nixos:/build" -w /build nixos/nix sh -c "
  echo 'system-features = kvm benchmark big-parallel nixos-test uid-range' >> /etc/nix/nix.conf
  nix --extra-experimental-features 'nix-command flakes' \
    run github:nix-community/nixos-generators -- \
    --format raw-efi --configuration ./configuration.nix -o /tmp/result
  cp -L /tmp/result/nixos.img /build/dist/nixos-kube-ready-arm64-raw-efi.img
  chmod 644 /build/dist/nixos-kube-ready-arm64-raw-efi.img"
```

주의점 셋:

1. **`system-features = kvm` 선언이 없으면 빌드가 시작조차 못 합니다.** 디스크 이미지 빌더가 `kvm` 기능을 요구하는데 Docker Desktop VM에는 `/dev/kvm`이 없습니다. 위 줄은 "KVM이 있다"고 nix에 알리는 우회이며, 실제로는 가속 없이 돌기 때문에 빌드 로그에 `error while reading directory ...: Invalid argument`가 대량으로 찍힙니다. 빌드는 완료되고 부팅도 확인됐지만 정상 경로는 아닙니다. 근본 해결은 Docker Desktop의 중첩 가상화 활성화(Apple M3 이상 + macOS 15 이상) 또는 `system.image.repart` 기반 빌드로 전환입니다.
2. **`raw-efi`의 출력은 파일이 아니라 `nixos.img`를 담은 디렉터리입니다.** 디렉터리째 `cp -r` 하면 nix store의 읽기 전용 퍼미션 때문에 `Permission denied`로 실패합니다. `build.sh`는 안쪽 이미지 파일만 꺼내도록 처리합니다.
3. **`-v nixcache:/nix`** 로 스토어를 유지하면 재빌드가 훨씬 빨라집니다.

> `configuration.nix`의 `allowUnsupportedSystem`은 aarch64 평가를 강제로 통과시키는 우회책입니다. 검증되지 않은 조합을 밀어붙인다는 뜻이므로 산출물은 반드시 부팅 검증 후 사용하세요.

---

## 🔍 로컬 박스 검증

배포 전 로컬에서 포장한 박스를 그대로 띄워봅니다.

```bash
vagrant box add nixos-local nixos/dist/dasomel-nixos-kube-ready-arm64-libvirt.box --force
mkdir -p /tmp/nixos-test && cd /tmp/nixos-test
printf 'Vagrant.configure("2") { |c| c.vm.box = "nixos-local" }\n' > Vagrantfile
vagrant up --provider qemu
vagrant ssh
# 확인 후
vagrant destroy -f && vagrant box remove nixos-local --all --force
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
