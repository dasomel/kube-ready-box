# test-vm 회귀 테스트 하네스

업로드 전 기본 회귀 검증을 저장소 내에서 고정 실행하기 위한 하네스입니다. Hypervisor가 필요한 matrix는 로컬/Claude QA에서 실행합니다.

## 단일 검증

```bash
cd test-vm/vmware
vagrant up
bash ../verify_box.sh vmware_desktop --strict-runtime --rfp-profile
```

## Matrix runner

```bash
# VMware
PROVIDER=vmware_desktop BOX=test/ubuntu-24.04 bash test-vm/matrix.sh

# VirtualBox
PROVIDER=virtualbox BOX=test/ubuntu-24.04-vbox bash test-vm/matrix.sh
```

`matrix.sh`는 Vagrant VM을 기동하고 공통 preflight/RFP profile을 실행한 뒤 machine-readable JSON evidence를 확인하고 VM을 destroy합니다.

## 전체 권장 matrix

Ubuntu 24.04/26.04 × amd64/arm64 × ext4/xfs × VirtualBox/VMware를 실제 artifact에 맞춰 반복 실행합니다. provider/architecture/filesystem이 선언되지 않은 경우 테스트를 PASS로 추정하지 않습니다.
