# Phase 1 — 변수화 + 4개 템플릿

날짜: 2026-06-13 / 상태: ✅ 완료 (독립 검증 통과)

## 설계
- `var.ubuntu_version`(default `"24.04"` 유지)으로 24.04/26.04 병행 빌드.
- ISO URL·체크섬을 `plugins.pkr.hcl` 내 **버전별 맵 local**(`iso_data`)로 재구성.
  4개 변수(`var.iso_url_amd64` 등) → `local.iso_url_amd64` 등 derived local로 전환.
- 26.04 빌드: `packer validate -var ubuntu_version=26.04 .` / `build.sh` 에 동일 var 전달.

## 변경 파일
| 파일 | 변경 |
|------|------|
| `packer/plugins.pkr.hcl` | iso 변수 4개 제거 → `locals.iso_data` 맵("24.04"/"26.04") + derived local 4개 |
| `packer/virtualbox-amd64.pkr.hcl` | `var.iso_*`→`local.iso_*`, `vm_name`/`output`→`${var.ubuntu_version}`, provisioner `ubuntu-tuning.sh` |
| `packer/virtualbox-arm64.pkr.hcl` | 동일 + shell-local `VM_NAME`/`BOX_NAME`/`VDI_SOURCE` 보간화 |
| `packer/vmware-amd64.pkr.hcl` | 동일 패턴 |
| `packer/vmware-arm64.pkr.hcl` | 동일 패턴 |
| `packer/scripts/ubuntu2404-tuning.sh` → `ubuntu-tuning.sh` | `git mv` 리네임, 제목/conf 파일명 버전 중립화(`99-ubuntu-tuning.conf`) |
| `packer/http/autoinstall-ext4/meta-data` | `instance-id`/`local-hostname` 버전 중립화 |
| `packer/http/autoinstall-xfs/meta-data` | 동일 |

## 검증 (agy 독립 워커)
| 체크 | 결과 |
|------|------|
| `packer fmt -check -recursive` | PASS |
| `build.sh validate` (24.04 기본) | PASS |
| **`packer validate -var ubuntu_version=26.04`** | **PASS** — `local.iso_data["26.04"]` 정상 조회 |
| 4개 템플릿+tuning 잔여 하드코딩 | 0건 |
| `shellcheck ubuntu-tuning.sh` | PASS |
| meta-data `24.04`/`2404` 잔존 | 0건 |

## 비고
- `ubuntu-tuning.sh` 실행 비트 없음(`100644`)은 **프로젝트 컨벤션**(모든 형제 스크립트 동일). Packer shell provisioner가 자체 `chmod +x` → 정상. 실수패턴 #2 비해당.
- `box_version` 변수는 ubuntu_version과 독립. 26.04 라인 첫 릴리스 버전은 Phase 5(릴리스)에서 결정.
- 잔여 `24.04` 문자열은 `plugins.pkr.hcl`의 iso_data 데이터값(의도)과 보조 스크립트(generate-sbom/license-info/upload-all → Phase 2·4에서 처리).
