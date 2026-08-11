#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
set -e

#=========================================
# NixOS Vagrant Box (libvirt) Packaging Script
# dasomel/nixos-kube-ready
#=========================================

# 인자로 받은 상대 경로는 호출자의 cwd 기준이므로 cd 전에 기억해 둔다.
CALLER_PWD="$PWD"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 파일명 규칙은 build.sh 및 upload-nixos.sh와 공유한다.
# shellcheck source=nixos/box-common.sh
. "${SCRIPT_DIR}/box-common.sh"

# 출력용 ANSI 색상 변수
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

DIST_DIR="dist"
ARCH=$(detect_arch)

# 박스는 항상 libvirt 형식으로 만든다. vagrant-qemu 플러그인이
#   provider(:qemu, box_format: "libvirt", ...)
# 로 선언돼 있어 macOS에서도 같은 박스를 쓰기 때문이다. provider를 "qemu"로 적으면
# `vagrant up --provider qemu`가 박스를 영영 찾지 못한다(레지스트리의 공개 qemu 박스들도
# 모두 libvirt 프로바이더로 등록돼 있다).
PROVIDER="libvirt"

show_usage() {
  cat <<EOF
Usage: $0 [-p PROVIDER] [IMAGE_PATH]

Package a NixOS disk image into a Vagrant Box (.box).

CURRENT PLATFORM:
  Platform: ${ARCH} ($(uname -m))

PROVIDERS:
  libvirt (기본)    raw 이미지 -> qcow2 박스.
                    Linux의 vagrant-libvirt와 macOS의 vagrant-qemu가 같은 박스를 쓴다
                    (vagrant-qemu가 box_format: "libvirt"로 선언돼 있다).
                    입력 기본값: ${DIST_DIR}/$(image_filename "${ARCH}" "raw-efi")
  vmware_desktop    vmdk -> vmx+vmdk 박스. VMware Fusion/Workstation용.
                    입력 기본값: ${DIST_DIR}/nixos-kube-ready-${ARCH}.vmdk

OPTIONS:
  -p, --provider    위 프로바이더 중 하나
  help, --help, -h  Show this help message

PREREQUISITES:
  - qemu-img (qemu-utils or qemu)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    help | --help | -h)
      show_usage
      exit 0
      ;;
    -p | --provider)
      PROVIDER="${2:-}"
      shift 2
      ;;
    *) break ;;
  esac
done

case "$PROVIDER" in
  libvirt | vmware_desktop) ;;
  *)
    echo -e "${RED}Error: Unsupported provider '${PROVIDER}' (libvirt | vmware_desktop)${NC}" >&2
    exit 1
    ;;
esac

# 1. 필수 도구(qemu-img) 존재 여부 검증
if ! command -v qemu-img >/dev/null 2>&1; then
  echo -e "${RED}Error: 'qemu-img' command is not installed or not in PATH.${NC}" >&2
  echo -e "${YELLOW}qemu-img is required to convert raw disk images to qcow2 format.${NC}" >&2
  echo -e "${YELLOW}Install qemu-utils (Ubuntu/Debian) or qemu (macOS via brew).${NC}" >&2
  exit 1
fi

# 2. 입력 raw 이미지 경로 결정 및 존재 여부 검증
# 인자 없으면 기본 산출물. 인자가 상대 경로면 호출자 cwd 기준 -> nixos/ 기준 순으로 찾는다.
if [ -n "${1:-}" ]; then
  case "$1" in
    /*) RAW_IMAGE="$1" ;;
    *)
      if [ -f "${CALLER_PWD}/$1" ]; then RAW_IMAGE="${CALLER_PWD}/$1"; else RAW_IMAGE="$1"; fi
      ;;
  esac
elif [ "$PROVIDER" = "vmware_desktop" ]; then
  RAW_IMAGE="${DIST_DIR}/nixos-kube-ready-${ARCH}.vmdk"
else
  RAW_IMAGE="${DIST_DIR}/$(image_filename "${ARCH}" "raw-efi")"
fi

if [ ! -f "$RAW_IMAGE" ]; then
  echo -e "${RED}Error: Input image file not found: ${RAW_IMAGE}${NC}" >&2
  echo -e "${YELLOW}Please build it first via ./build.sh raw (or the vmware format) or specify a valid path.${NC}" >&2
  exit 1
fi

echo -e "${BLUE}=== Packaging NixOS Vagrant Box (${PROVIDER}) ===${NC}"
echo -e "Input Image: ${RAW_IMAGE}"

# 3. 임시 작업 디렉터리 생성 및 자동 정리 트랩 설정
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

if [ "$PROVIDER" = "vmware_desktop" ]; then
  # VMware 박스는 vmx + vmdk + metadata.json 구성이다.
  # 디스크 컨트롤러는 SATA로 붙인다. Apple Silicon Fusion에서 검증된 ARM64 박스들이
  # nvme를 끄고 sata0:0에 디스크를 무는 구성을 쓴다.
  echo -e "${YELLOW}Copying VMDK into box layout...${NC}"
  cp "$RAW_IMAGE" "${TMP_DIR}/disk.vmdk"
  chmod u+w "${TMP_DIR}/disk.vmdk"

  cat <<EOF > "${TMP_DIR}/metadata.json"
{"architecture":"${ARCH}","provider":"vmware_desktop"}
EOF

  # 이 VMX는 Apple Silicon Fusion에서 실제로 동작하는 ARM64 박스(bento/ubuntu-24.04
  # vmware_desktop)의 설정을 그대로 따른 것이다. 최소 구성으로 직접 쓰면 vmrun이
  # "Unexpected signal: 11"로 죽는다 — svga/pcibridge/monitor 항목이 빠지면 안 된다.
  # guestOS는 힌트 값이라 NixOS 전용 토큰이 없어 arm-ubuntu-64를 그대로 쓴다.
  cat <<'EOF' > "${TMP_DIR}/nixos-kube-ready.vmx"
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "21"
firmware = "efi"
guestOS = "arm-ubuntu-64"
displayName = "nixos-kube-ready"
memsize = "2048"
numvcpus = "2"
cpuid.coresPerSocket = "2"
numa.autosize.vcpu.maxPerVirtualNode = "2"
monitor.phys_bits_used = "36"
hpet0.present = "TRUE"
vhv.enable = "FALSE"
bios.bootOrder = "hdd,cdrom"
sata0.present = "TRUE"
sata0.pciSlotNumber = "32"
sata0:0.present = "TRUE"
sata0:0.fileName = "disk.vmdk"
sata0:0.redo = ""
nvme0.present = "FALSE"
scsi0.present = "FALSE"
scsi0.pciSlotNumber = "16"
scsi0.virtualDev = "lsilogic"
scsi0:0.redo = ""
pciBridge0.present = "TRUE"
pciBridge0.pciSlotNumber = "17"
pciBridge4.present = "TRUE"
pciBridge4.virtualDev = "pcieRootPort"
pciBridge4.functions = "8"
pciBridge4.pciSlotNumber = "21"
pciBridge5.present = "TRUE"
pciBridge5.virtualDev = "pcieRootPort"
pciBridge5.functions = "8"
pciBridge5.pciSlotNumber = "22"
pciBridge6.present = "TRUE"
pciBridge6.virtualDev = "pcieRootPort"
pciBridge6.functions = "8"
pciBridge6.pciSlotNumber = "23"
pciBridge7.present = "TRUE"
pciBridge7.virtualDev = "pcieRootPort"
pciBridge7.functions = "8"
pciBridge7.pciSlotNumber = "24"
svga.autodetect = "TRUE"
svga.guestBackedPrimaryAware = "TRUE"
svga.vramSize = "268435456"
vmotion.checkpointFBSize = "134217728"
vmotion.checkpointSVGAPrimarySize = "268435456"
vmotion.svga.graphicsMemoryKB = "262144"
vmotion.svga.mobMaxSize = "268435456"
usb_xhci.present = "TRUE"
usb_xhci.pciSlotNumber = "192"
usb.present = "FALSE"
usb.pciSlotNumber = "-1"
ehci.present = "FALSE"
ehci.pciSlotNumber = "-1"
sound.present = "FALSE"
sound.autodetect = "TRUE"
sound.fileName = "-1"
sound.startConnected = "FALSE"
parallel0.present = "FALSE"
vmci0.present = "TRUE"
vmci0.pciSlotNumber = "35"
hgfs.linkRootShare = "TRUE"
hgfs.mapRootShare = "TRUE"
isolation.tools.hgfs.disable = "FALSE"
tools.syncTime = "TRUE"
tools.upgrade.policy = "upgradeAtPowerCycle"
powerType.powerOff = "soft"
powerType.powerOn = "soft"
powerType.reset = "soft"
powerType.suspend = "soft"
EOF
  BOX_FILES="disk.vmdk metadata.json nixos-kube-ready.vmx Vagrantfile"
else
  # 4. qemu-img info로 가상 디스크 크기(바이트) 추출 후 GiB 올림 계산
  # vagrant-libvirt metadata.json 규격에 맞추기 위해 바이트를 GiB 정수로 변환한다.
  # 백킹 파일 등으로 virtual-size가 여러 번 나올 수 있으므로 첫 항목만 취한다.
  bytes=$(qemu-img info --output=json "$RAW_IMAGE" | awk -F: '/"virtual-size"/ {gsub(/[^0-9]/, "", $2); print $2; exit}')

  if [[ -z "$bytes" || ! "$bytes" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Error: Failed to determine virtual-size from ${RAW_IMAGE}${NC}" >&2
    exit 1
  fi

  VIRTUAL_SIZE_GIB=$(( (bytes + 1073741823) / 1073741824 ))

  echo -e "${YELLOW}Converting raw image to compressed qcow2 (box.img)...${NC}"
  qemu-img convert -O qcow2 -c "$RAW_IMAGE" "${TMP_DIR}/box.img"

  cat <<EOF > "${TMP_DIR}/metadata.json"
{"provider":"libvirt","format":"qcow2","virtual_size":${VIRTUAL_SIZE_GIB}}
EOF
  BOX_FILES="box.img metadata.json Vagrantfile"
fi

# 5. 내장 Vagrantfile
# 하나의 박스로 Linux(libvirt)와 macOS(vagrant-qemu)를 모두 커버한다.
# Vagrant는 실제로 사용하는 프로바이더의 블록만 평가하므로 둘을 함께 둬도 안전하다.
# 기본 공유 폴더는 끈다: 게스트에 vboxsf/open-vm-tools가 없고, qemu 프로바이더에서는
# SMB 폴백이 호스트 자격증명을 대화형으로 물어 자동화가 그 자리에서 멈춘다.
cat <<'EOF' > "${TMP_DIR}/Vagrantfile"
Vagrant.configure("2") do |config|
  config.vm.synced_folder ".", "/vagrant", disabled: true

  # Vagrant 기본값인 로그인 셸(bash -l)로 감싸면 NixOS 게스트에서 명령의 stdout이
  # Vagrant에 전달되지 않는다. 그 결과 SSH 키 교체 단계의 `sshd -T | grep key` 결과가
  # 비어 `odd number of arguments for Hash`로 죽는다. 비로그인 셸로 고정한다.
  config.ssh.shell = "bash"

  config.vm.provider :libvirt do |libvirt|
    libvirt.driver = "kvm"
    libvirt.memory = 2048
    libvirt.cpus = 2
  end

  # aarch64 펌웨어(edk2)는 플러그인이 qemu_dir에서 읽으므로 박스에 넣지 않는다.
  config.vm.provider :qemu do |qe|
    qe.arch = "aarch64"
    qe.machine = "virt,accel=hvf,highmem=on"
    qe.cpu = "host"
    qe.smp = "2"
    qe.memory = "2G"
    qe.net_device = "virtio-net-device"
  end
end
EOF

# 6. 박스 아티팩트 tar.gz 압축 및 출력 저장
mkdir -p "$DIST_DIR"
OUTPUT_BOX=$(box_filename "$ARCH" "$PROVIDER")
OUTPUT_BOX_PATH="${SCRIPT_DIR}/${DIST_DIR}/${OUTPUT_BOX}"

echo -e "${YELLOW}Creating Vagrant box archive (${OUTPUT_BOX})...${NC}"
# 박스 규격상 구성 파일이 아카이브 최상위에 평평하게 있어야 하므로 cd 후 압축한다.
(
  cd "$TMP_DIR"
  # shellcheck disable=SC2086  # BOX_FILES는 의도적으로 단어 분리한다
  tar czf "$OUTPUT_BOX_PATH" $BOX_FILES
)

# 7. 최종 결과 출력
if [ -f "$OUTPUT_BOX_PATH" ]; then
  box_size=$(du -h "$OUTPUT_BOX_PATH" | cut -f1)
  echo -e "${GREEN}✅ Vagrant box successfully packaged!${NC}"
  echo -e "${GREEN}📦 Output: ${DIST_DIR}/${OUTPUT_BOX} (${box_size})${NC}"
else
  echo -e "${RED}Error: Failed to create output box archive.${NC}" >&2
  exit 1
fi
