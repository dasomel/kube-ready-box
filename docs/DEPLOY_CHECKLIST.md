# 배포 체크리스트

## 1. 로컬 빌드 및 테스트

```bash
cd packer
./build.sh init
./build.sh validate
./build.sh vmware-arm64
# 또는 ./build.sh virtualbox-amd64
cd ../test-vm/vmware
vagrant up
./verify_box.sh --rfp-profile
vagrant destroy -f
```

## 2. Immutable release evidence

릴리스 버전은 삭제하지 않고 immutable artifact로 보존한다.

```bash
VERSION=vX.Y.Z ./tools/release-promote.sh init
```

`release-evidence/$VERSION/`에 provider/arch/filesystem 검증 결과, SHA256SUMS, SBOM, security report, license report를 보관한다.

## 3. Candidate → staging → production

`promote`는 상태 파일에 기록된 현재 stage를 기준으로 한 단계씩만 전진한다. 같은 명령을 두 번 실행해야 production까지 도달한다.

```bash
# 1단계: candidate -> staging (5개 evidence 파일이 모두 존재/파싱 가능해야 함)
VERSION=vX.Y.Z ./tools/release-promote.sh promote

# staging에서 실제 provider/architecture/filesystem smoke test 수행 후 verification.json 갱신

# 2단계: staging -> production (매트릭스 전 항목 PASS 필요)
VERSION=vX.Y.Z ./tools/release-promote.sh promote
```

매 전이는 `release-evidence/$VERSION/promotion-log.tsv`에 (timestamp, from_stage, to_stage) 한 줄로 기록된다. production은 종착 stage이며, 여기서 다시 `promote`를 실행하면 거부된다.

언제든 아래로 현재 상태를 점검할 수 있다:

```bash
VERSION=vX.Y.Z ./tools/release-promote.sh verify
```

`verify`는 stage=candidate에서는 evidence 준비 상태만 보고하고(부족해도 exit 0), stage=staging/production에서는 evidence가 없거나 무효하면 반드시 실패(exit 1)한다. `verification.json`과 required-matrix 계약은 [release-evidence/README.md](../release-evidence/README.md)를 참고.

## 4. Vagrant Cloud 업로드

검증 완료된 provider만 명시적으로 업로드한다.

```bash
PROVIDERS=vmware_desktop UBUNTU_VERSION=24.04 VERSION=vX.Y.Z ./upload-boxes.sh
```

이미 공개된 버전은 덮어쓰거나 삭제하지 않는다. 새 빌드는 새 immutable version으로 발행한다.

## 5. 배포 후 검증

```bash
mkdir test-download && cd test-download
vagrant init dasomel/ubuntu-24.04-ext4
vagrant up --provider=vmware_desktop
vagrant ssh -c "uname -a"
vagrant ssh -c "cat /etc/vagrant-box/info.txt"
vagrant destroy -f
```

## 6. Rollback

문제 발생 시 이전 정상 버전을 pin한다. Vagrant Cloud version이나 Git tag를 삭제하지 않는다.

`PREVIOUS_VERSION`은 반드시 stage가 `staging` 또는 `production`인 known-good이어야 한다. candidate로는 롤백할 수 없다(검증되지 않은 버전을 안전한 대상으로 취급하지 않기 위함).

```bash
VERSION=vX.Y.Z PREVIOUS_VERSION=vX.Y.Z-previous ./tools/release-promote.sh rollback
```

rollback 결과는 두 곳에 기록된다:

- `release-evidence/rollback/rollback-pin.env` — 현재 pin 한 건(매 롤백마다 덮어씀)
- `release-evidence/rollback/history.tsv` — 모든 롤백의 불변 이력(누적, timestamp/from_version/to_version/reason)

또한 롤백된 버전(`VERSION`) 자신의 `release-state.env`는 `stage=rolled_back`으로 갱신되고 그 `promotion-log.tsv`에도 전이가 기록되어, 해당 버전이 더 이상 운영 중이 아님을 표시한다.

## 7. GitHub Release

```bash
gh release create vX.Y.Z --title "vX.Y.Z - RELEASE_TITLE"
```

GitHub Release에는 CHANGELOG와 SBOM/security/license evidence를 연결한다.
