# Phase 5 — 검증 빌드 & 릴리스 (사용자 직접 실행)

상태: 검증 빌드 1회 ✅ 통과 / 릴리스 ⏳ 대기

## 검증 빌드 결과 (2026-06-13)

대상: `./build.sh virtualbox-arm64 --fs=xfs --version=26.04` (가장 위험한 조합)
판정: **OS 레벨 26.04 빌드 성공.** 유효한 2.4G 박스 산출.

| 검증 포인트 | 결과 |
|-------------|------|
| ISO (Phase 0 체크섬) 다운로드·검증 | ✅ `c9aa567e…439fdd` 일치 |
| 변수 전파 (`-var ubuntu_version=26.04`) | ✅ 런타임 확인 |
| autoinstall 완료 (network `en*`, XFS prjquota storage) | ✅ |
| 전 프로비저닝(00~99) on 커널 7.0 | ✅ 모두 Complete |
| 리네임 `ubuntu-tuning.sh` | ✅ "Ubuntu Version-specific Tuning … Complete" |
| `license-info.sh` (heredoc 변경) / `generate-sbom.sh` | ✅ Complete |
| 박스 산출물 (metadata.json/Vagrantfile/box.ovf/disk001.vmdk) | ✅ 유효 |
| 박스 OS hint | ✅ `Ubuntu_arm64` |

### ⚠️ 알려진 quirk (마이그레이션 무관, 기존 동작)
VirtualBox ARM64(macOS Silicon)는 OVF export 불가 → 커스텀 shell-local post-processor가
박스를 직접 만들고 **VM을 먼저 unregister**. 이후 packer 내장 정리가
`Could not find a registered machine` → **packer는 errored / "no artifacts" 로 종료하지만 박스는 정상**.
- 증거: 2026-05-01 24.04 빌드 로그(xfs·ext4)에 동일 패턴, 해당 박스가 Vagrant Cloud에 출시됨.
- 영향: `packer build` 종료코드 비0. **CI(build-arm64.yml)·업로드가 종료코드에 의존하면 박스가 유효해도 실패 처리될 수 있음** → 별도 확인 권장(아래).

### 후속 확인 권장 (선택)
- [ ] CI ARM64가 이 종료코드 quirk를 어떻게 처리하는지 확인 (24.04는 어떻게 출시됐나: 수동 upload vs CI continue-on-error vs box-존재 체크)
- [ ] 원하면 mistake-pattern #11로 등재 (`/add-mistake`)
- [ ] ext4 조합 / VMware 프로바이더는 미검증 (이번엔 1회 검증 범위)

---

## (이하 릴리스 절차) — 사용자 직접 실행

> Phase 1~4로 코드/설정/CI/문서는 26.04 병행 준비 완료(정적 검증 통과).
> 남은 것은 **커널 7.0 위 실빌드 1회 검증**과 릴리스. 되돌릴 수 없는 단계이므로 사람이 진행.

## 사전 조건
- [ ] VirtualBox **7.2.6+** (ARM64 scancode 이슈 회피 — 실수패턴 #4)
- [ ] VMware Fusion Pro/Player (headless 빌드 — 실수패턴 #5)
- [ ] `cd packer && ./build.sh init`

## 1. 검증 빌드 (가장 위험한 조합부터)
26.04 + 커널 7.0에서 튜닝 스크립트(`ubuntu-tuning.sh`)·autoinstall이 실제 동작하는지 확인.
```bash
# XFS prjquota가 가장 민감 → 먼저
./build.sh vmware-arm64 --fs=xfs --version=26.04
# 통과 시 ext4
./build.sh vmware-arm64 --version=26.04
```
- [ ] autoinstall 정상 완료 (네트워크 `en*` 매칭, storage 구성)
- [ ] 부팅 후 `07-check-tuning.sh` 통과
- [ ] `kubeadm` 전제조건: cgroup v2(`stat -fc %T /sys/fs/cgroup`=cgroup2fs), 모듈(overlay/br_netfilter), swap off 확인
- [ ] `ubuntu-tuning.sh` sysctl/THP/systemd-oomd 적용 확인 (커널 7.0 회귀 여부)
- [ ] SBOM/`/etc/vagrant-box/info.txt`에 **26.04** 자동 표기 확인

## 2. 전체 빌드 (4 프로바이더)
```bash
./build.sh all --version=26.04            # ext4 4종
./build.sh all --fs=xfs --version=26.04   # xfs 4종
```

## 3. 릴리스 (되돌릴 수 없음 — Opus 검토 후)
- [ ] 26.04 라인 첫 box semver 결정 (예: 0.1.0) — `upload-boxes.sh`의 `VERSION` 및 필요시 `plugins.pkr.hcl` box_version
- [ ] `UBUNTU_VERSION=26.04 ./upload-boxes.sh` (또는 `./upload-boxes.sh --version=26.04`)
- [ ] Vagrant Cloud `dasomel/ubuntu-26.04-ext4` / `-xfs` 생성 확인
- [ ] CHANGELOG `[Unreleased]` → 릴리스 번호/날짜 확정
- [ ] CI: Actions → Run workflow → ubuntu_version=**26.04** 로 재현 빌드(선택)

## 알려진 리스크 (Phase 0 발견)
| 리스크 | 빌드 중 확인 포인트 |
|--------|---------------------|
| 커널 Linux 7.0 | THP 경로/oomd/journald 설정 적용 여부 |
| cgroup v1 제거 | v2 unified만 존재 (24.04도 동일하므로 통과 예상) |
| autoinstall 스키마 | `version:1` 그대로 — 실패 시 subiquity 로그 확인 |
