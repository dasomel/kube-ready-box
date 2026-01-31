# Ralph Task: 빌드 검증 + 디스크 튜닝 스크립트 개선

## 목표

1. 빌드 멈춤 문제 해결 확인 (timedatectl 제거 후 정상 빌드 여부)
2. 05-disk-tuning.sh와 07-check-tuning.sh의 품질 개선

## 컨텍스트

- 프로젝트: Kube Ready Box (Kubernetes-ready Vagrant Box)
- 관련 문서: CLAUDE.md
- 현재 상태:
  - **빌드 멈춤 수정 완료**: timedatectl → ln -sf로 변경됨 (검증 필요)
  - 05-disk-tuning.sh는 `set -e`만 사용 중 (pipefail 누락)
  - 07-check-tuning.sh에 디스크 튜닝 검증 항목 부족

## 작업 목록

### 빌드 검증 (우선)
1. [ ] Packer 빌드 실행하여 멈춤 없이 완료되는지 확인
2. [ ] 빌드 실패 시 원인 파악 및 수정

### 디스크 튜닝 개선
3. [ ] 05-disk-tuning.sh에 `set -euo pipefail` 적용
4. [ ] 07-check-tuning.sh에 `set -euo pipefail` 적용
5. [ ] 07-check-tuning.sh에 디스크 튜닝 검증 섹션 추가:
   - I/O 스케줄러 상태 확인
   - Read-ahead 값 확인
   - noatime 마운트 옵션 확인
   - LVM auto-extend 서비스 상태 확인
6. [ ] shellcheck 경고 해결

## 제약 조건

- packer/scripts/*.sh 파일은 `set -euo pipefail` 필수
- 기존 기능 유지 (LVM 확장, I/O 스케줄러, read-ahead, noatime)
- Ubuntu 24.04 호환성 유지
- VirtualBox/VMware 둘 다 동작해야 함
- 출력 형식은 기존 07-check-tuning.sh와 일관성 유지 (`[N] 섹션명` 형식)

## 완료 조건

다음 조건을 모두 만족하면 작업 완료:

1. [ ] Packer 빌드가 멈춤 없이 완료됨
2. [ ] shellcheck packer/scripts/05-disk-tuning.sh 통과
3. [ ] shellcheck packer/scripts/07-check-tuning.sh 통과
4. [ ] 07-check-tuning.sh에 디스크 튜닝 검증 섹션 존재 (최소 4개 항목)
5. [ ] 두 스크립트 모두 `set -euo pipefail` 포함

## 검증 명령어

```bash
# 빌드 테스트 (vmware-arm64 또는 현재 환경에 맞는 빌드)
cd packer && ./build.sh vmware-arm64

# 쉘 스크립트 검증
shellcheck packer/scripts/05-disk-tuning.sh
shellcheck packer/scripts/07-check-tuning.sh

# set -euo pipefail 확인
grep -q "set -euo pipefail" packer/scripts/05-disk-tuning.sh && echo "05: OK" || echo "05: FAIL"
grep -q "set -euo pipefail" packer/scripts/07-check-tuning.sh && echo "07: OK" || echo "07: FAIL"

# 디스크 검증 섹션 확인
grep -c "디스크\|Disk\|I/O\|scheduler\|noatime" packer/scripts/07-check-tuning.sh
```

## 반복 지시사항

각 반복에서:
1. 작업 목록에서 미완료 항목 확인
2. 한 번에 하나씩 작업 수행
3. 검증 명령어 실행
4. 실패 시 수정 후 재검증
5. 모든 조건 만족 시 종료 메시지 출력

## 종료 조건

모든 완료 조건이 만족되면:
```
=== RALPH TASK COMPLETE ===
All tasks finished successfully.
```
메시지를 출력하세요.
