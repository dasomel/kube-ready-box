# lima(vz)에서 박스 이미지 검증 PoC

상태: **PoC**. 빌드 경로(`packer/`)는 바꾸지 않았다. Vagrant 박스를 변환해 lima(vz)에서 부팅하고,
박스 검증과 단일 노드 kubeadm 클러스터까지 확인했다. 재현 스크립트는 `test-vm/lima/`에 있다.

## 왜

colima 기본 이미지(Ubuntu 24.04, ext4, k3s)에서 얻은 결과는 박스 이미지(26.04, XFS, kubeadm)에 대한
증거가 아니다. colima 는 colima-core 가 아닌 이미지를 검증에서 거부하므로(`forceDiskImage` 는
"completely unsupported"), colima 가 아니라 lima 를 직접 쓴다.

## 결과 (2026-11-08, macOS Apple Silicon, lima 2.2.1)

입력: 로컬 빌드 `ubuntu-26.04-ext4-virtualbox-arm64.box` (manifest build_date 2026-09-29, 커널 7.0.0-34).

| 단계 | 결과 |
|---|---|
| lima(vz) 부팅 | READY |
| `k8s-node-preflight` (STRICT_RUNTIME=0) | failures=0, unknowns=1 (containerd 미설치, 설계상) |
| RFP 프로필 (`verify_box.sh` 원격 블록) | PASS, failures=0 |
| 런타임 설치 | containerd 2.2.2 (SystemdCgroup=true), kubeadm v1.37.2 |
| `k8s-node-preflight` (STRICT_RUNTIME=1) | failures=0, unknowns=0 |
| `kubeadm init` | 성공, WARNING 0건 |
| 클러스터 | Flannel v0.28.10, 노드 Ready, kube-system 전부 Running |
| Service 경로 | `nginx.default.svc.cluster.local` 응답 확인 (클러스터 DNS + kube-proxy) |
| RFP 프로필 (STRICT_RUNTIME=1) | PASS, failures=0, unknowns=3 (아래) |

남은 UNKNOWN: `air_gapped_install`(요청 안 함), `dns_readiness`(노드 resolver 로 보는 검사라 클러스터가
떠 있어도 UNKNOWN), `sbom`(이 로컬 박스의 `/etc/vagrant-box/`에 SBOM 파일 없음).

## 박스를 그대로 쓸 수 없는 이유 (정식 lima 변형에 필요한 변경)

1. **cloud-init 이 꺼져 있다.** `/etc/cloud/cloud-init.disabled`(설치기 마커),
   `99-installer.cfg`(`datasource_list: [None]` + 설치 user-data),
   `00-subiquity-disable-cloudinit-networking.cfg`. lima 는 NoCloud(cidata)로 사용자, SSH 키,
   guest agent 를 넣으므로 이를 지우고 `[NoCloud, None]`을 둬야 한다. 0.3.1 에서 GRUB 의
   `ds=nocloud-net` 인자를 지웠기 때문에(`99-cleanup.sh`) 켜도 빌드 호스트에 접속하지 않는다.
   `prepare-image.sh`는 이 변경을 QEMU(hvf) 부팅 한 번으로 적용한다.
   입력 박스에 이 GRUB 정리가 들어 있어야 한다. PoC 박스(2026-09-29 빌드)는 `/proc/cmdline`에
   `autoinstall`/`ds=` 인자가 없음을 확인했다. 그보다 오래된 박스는 쓰지 않는다.
2. **가상 디스크가 977GiB 다.** lima 는 디스크를 줄이지 못해(`disk shrinking is not supported`)
   `disk: 1000GiB` 이상을 요구한다. 실제 사용량은 약 4.2GiB(qcow2).
3. **디스크 튜닝이 `vd*`를 모른다.** `05-disk-tuning.sh`, `07-check-tuning.sh`는 `sd*`, `nvme*`만 본다.
   vz 에서는 `vda`(virtio-blk)다. PoC 에서 `vda`가 `mq-deadline`/8192 였지만 저장소 스크립트가 한 일은 아니다.
4. **qcow2 산출물이 없다.** 정식 지원은 변환 대신 빌드 산출물로 내야 한다. Packer QEMU 템플릿을 추가하면
   Ubuntu 템플릿 묶음 일관성 검사(`tools/template-consistency-check.sh`)도 함께 바꿔야 한다.

## 미해결 / 미검증

- `systemd-networkd-wait-online` 이 부팅 때 타임아웃으로 실패한다. 네트워크와 클러스터 동작에는 영향이
  없었다. `/run/systemd/network/zzzz-dracut-default.network`를 의심하지만 확인하지 않았다.
- XFS 박스(prjquota), 다중 노드(노드 간 네트워크, 스케줄링), 배포된 v0.3.1 박스는 검증하지 않았다.
- `prepare-image.sh`는 arm64 Ubuntu 박스만 대상으로 한다. Rocky(cloud-init 없음)는 해당하지 않는다.
- 게스트 스크립트는 pkgs.k8s.io 키와 Flannel 매니페스트를 버전으로만 고정하고 지문/체크섬은 검증하지
  않는다. PoC 하네스라서 받아들인 한계이며, 빌드 경로에 쓰는 입력은 아니다.

## 재현

```bash
bash test-vm/lima/prepare-image.sh packer/output-vagrant/ubuntu-26.04-ext4-virtualbox-arm64.box /path/krb.qcow2
bash test-vm/lima/run.sh /path/krb.qcow2      # KEEP=1 이면 인스턴스를 남긴다
```

필요: lima(`limactl`), Homebrew `qemu`(qemu-img, qemu-system-aarch64), Vagrant insecure key
(`~/.vagrant.d/insecure_private_keys/vagrant.key.rsa`), 게스트의 인터넷 접속(apt, pkgs.k8s.io, 이미지 pull).
