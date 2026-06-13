# Phase 7 — CI ARM64 출시 갭 수정

날짜: 2026-06-13 / 상태: ✅ 수정 (YAML 검증 통과)

## 발견 (조사)
- `packer build`는 VirtualBox ARM64에서 커스텀 post-processor가 박스 생성 후 VM을 unregister →
  내장 정리가 "machine not found"로 **비0 종료**(박스는 유효). [phase-5 참고](./phase-5-release.md)
- `build.sh`는 packer 비0이면 박스 존재 무관 `return 1` (build.sh L283/L310).
- `build-arm64.yml`은 packer 직접 호출, 스텝 실패 시 잡 중단, `publish`는 `needs.*.result=='success'` 게이트.
  → **유효 ARM64 박스도 CI로는 출시되지 않음.**
- 기존 24.04 ARM64는 로컬 `upload-boxes.sh`(박스 존재만 확인, L51)로 **수동 출시**한 것으로 추정.
- 결론: 마이그레이션과 무관한 **기존 갭**. AMD64 경로는 해당 없음(정상 export).

## 수정 (`.github/workflows/build-arm64.yml`, VirtualBox ARM64 잡만)
1. **Packer Build** 스텝: 알려진 cleanup quirk 주석 + `|| echo "::warning::..."`로 비0 종료 허용.
2. **Verify Box File** 스텝을 **진짜 성공 게이트**로 승격:
   - 박스 파일 부재 시 `::error::` + `exit 1` (실제 빌드 실패는 여전히 잡 실패)
   - `tar -tzf`로 아카이브 무결성 검증(truncation/부분 export 차단)
- VMware ARM64 잡은 OVF export 정상이라 미변경.

## 효과
- 유효 ARM64 박스 → CI에서 publish 단계까지 도달(자동 출시 가능).
- 실제 빌드 실패(박스 미생성/손상) → Verify에서 잡 실패(거짓 성공 방지).

## 검증
- `python3 yaml.safe_load` → YAML OK
- 변경 범위: VBox ARM64 빌드/검증 스텝만 (grep 확인)

> 후속: 실제 GitHub Actions에서 `workflow_dispatch`(ubuntu_version=26.04, publish=true)로 1회 검증 권장.
