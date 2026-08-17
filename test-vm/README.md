# test-vm 회귀 테스트 하네스

업로드 전 기본 회귀 검증을 저장소 내에서 고정 실행하기 위한 하네스입니다.

## 사용법

```bash
# VMware 검증
cd test-vm/vmware
vagrant up
./verify_box.sh

# VirtualBox 검증
cd test-vm/virtualbox
vagrant up
./verify_box.sh
```

`verify_box.sh`는 공통 하네스(`test-vm/verify_box.sh`)를 호출하며, 항목 실패 시 non-zero로 종료합니다.

## 검증 항목

- OS/커널/아키텍처
- 필수 패키지(curl, git, vim, net-tools)
- K8s 전제조건(swap off, IPv6 off, br_netfilter/overlay)
- 디스크/메모리 상태 출력
