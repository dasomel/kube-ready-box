# 배포 체크리스트

## 1. 릴리스 빌드와 후보 검증

정기 Box CVE 스캔이 실패하면(배포판이 매주 패치를 낸다) 아래 순서로 새 버전을 만든다. 기존 버전은 덮어쓰지 않는다.
각 단계는 한 명령이고 다시 실행해도 안전하다. 산출물은 `packer/dist/`(박스)와 `packer/dist/evidence/`(증거)에 쌓인다.
`dist` 에 이전 릴리스 `.box` 가 남아 있으면 `evidence.py` 가 거부하니 치우거나 새 디렉터리를 쓴다.

```bash
# 0) 최초 1회: 스캔용 Linux VM(Lima krbscan) + 고정 버전 Trivy
tools/release/setup-scan-vm.sh

# 1) amd64: build-amd64.yml 을 24.04 / 26.04 로 두 번 dispatch (filesystem=both)
gh workflow run build-amd64.yml -f ubuntu_version=24.04 -f filesystem=both
gh workflow run build-amd64.yml -f ubuntu_version=26.04 -f filesystem=both
#    끝나면 run id 를 적어 두고 artifact 를 받아 릴리스 이름(<short>-virtualbox-amd64-<ver>.box)으로 packer/dist 에 둔다
gh run download <run-id> -D /tmp/amd64 && cp /tmp/amd64/*/*.box packer/dist/   # 이름에서 -<ver> 맞추기

# 2) arm64: 로컬 직렬 빌드(대상당 1회 재시도, dist 에 있으면 건너뜀). 실패한 대상 수가 종료 코드
tools/release/build-arm64.sh --ubuntu-version 0.3.5 --rocky-version 0.1.4

# 3) 박스마다 후보 게이트: scan(Trivy, PASS 만 통과) -> boot(vmware_desktop/arm64 만, 나머지는 SKIPPED)
for b in packer/dist/*-0.3.5.box packer/dist/rocky-*-0.1.4.box; do tools/release/verify-candidate.sh "$b"; done

# 4) 증거: BOX-SHA256SUMS 와 v0.3.5-evidence.json (스캔/부팅이 하나라도 PASS 가 아니면 거부)
tools/release/evidence.py --release v0.3.5 --source-commit "$(git rev-parse --short HEAD)" \
  --trigger "<무엇 때문에 재빌드했나>" --dist packer/dist --expect-version rocky=0.1.4 \
  --ci-run ubuntu-24.04-ext4=<run-id> --ci-run ubuntu-24.04-xfs=<run-id> \
  --ci-run ubuntu-26.04-ext4=<run-id> --ci-run ubuntu-26.04-xfs=<run-id> [--extra-image nixos.json]
cp packer/dist/v0.3.5-evidence.json docs/releases/   # *-evidence.json 은 .gitignore 대상이라 커밋하려면 git add -f

# 5) 카탈로그: 후보가 아니라 실제 Release URL 로 site/boxes/ 갱신 (docs/box-distribution.md)
tools/box-catalog.py add --catalog site/boxes/<short>.json --name dasomel/<short> --version 0.3.5 \
  --provider <p> --arch <a> --box packer/dist/<file>.box --url <release asset url>

# 6) draft Release 에 .box + BOX-SHA256SUMS + evidence.json 업로드 -> 업로드된 asset digest 를 로컬 sha256 과 비교
gh release create v0.3.5 --draft --title "v0.3.5 - <제목>" packer/dist/*-0.3.5.box packer/dist/rocky-*-0.1.4.box \
  packer/dist/BOX-SHA256SUMS docs/releases/v0.3.5-evidence.json
gh release view v0.3.5 --json assets --jq '.assets[]|"\(.digest) \(.name)"'   # BOX-SHA256SUMS 와 일치해야 한다

# 7) 일치하면 publish, 카탈로그 PR 을 main 에 머지(pages.yml 이 배포)
gh release edit v0.3.5 --draft=false
```

- `verify-candidate.sh` 의 `boot=SKIPPED(...)` 는 PASS 가 아니다. amd64 부팅 증거는 1)의 `build-amd64.yml` run 이다(`--ci-run`).
  Guest 점검은 `test-vm/guest-check.sh` 하나를 워크플로와 이 스크립트가 같이 쓴다.
- 부팅 재시도는 같은 명령을 다시 실행하면 `boot-<short>-try<N>.log` 가 늘어나고 `attempts` 에 이력이 남는다.
- **Rocky 교훈**: 재빌드를 publish 하기 전에 배포 중인 박스와 후보의 `rpm -qa` 를 비교한다(errata 날짜만으로는
  배포 중인 박스에 그 패치가 없다는 증명이 안 된다). 차이가 없으면 새 버전을 만들지 않는다.
- 스캔은 박스를 풀어 패키지 DB 만 읽는다(모든 Ubuntu 박스가 VG `ubuntu-vg` 라 한 번에 하나만; 잠금은 자동).

수동 확인용 로컬 부팅은 `./packer/build.sh vmware-arm64` 후 `test-vm/vmware` 에서 `vagrant up` / `../verify_box.sh vmware_desktop --rfp-profile` / `vagrant destroy -f` 이다.

## 2. Immutable release evidence

릴리스 버전은 삭제하지 않고 immutable artifact로 보존한다.

```bash
VERSION=vX.Y.Z ./tools/release-promote.sh init
```

`release-evidence/$VERSION/`에 provider/arch/filesystem 검증 결과, SHA256SUMS, SBOM, security report, license report를 보관한다.

`promote`가 evidence를 검증할 때 `RUN_RUST_VERIFIER=1`을 붙이면 `rust/kube-ready-verifier`의
`verify-evidence` 서브커맨드로 같은 5개 파일을 독립적으로 재검증한다(#12). 두 검증기가 어긋나면
(검증기 드리프트) promote가 실패하며 원인을 출력한다 — 기본은 꺼져 있어 기존 동작에 영향 없음.

```bash
ARTIFACT_DIR=packer/dist RUN_RUST_VERIFIER=1 VERSION=vX.Y.Z ./tools/release-promote.sh promote
```

## 3. Candidate → staging → production

`promote`는 상태 파일에 기록된 현재 stage를 기준으로 한 단계씩만 전진한다. 같은 명령을 두 번 실행해야 production까지 도달한다.

```bash
# 1단계: candidate -> staging (5개 evidence 파일이 모두 존재/파싱 가능해야 함)
# 추가 게이트: security/license 리포트 status가 정확히 PASS, SHA256SUMS에 나열된 파일이
# ARTIFACT_DIR 아래에 존재하고 해시 일치(.box는 packer/dist에 있으므로 ARTIFACT_DIR=packer/dist).
# UNKNOWN은 기본 차단이며 ALLOW_UNKNOWN_EVIDENCE=1로만 경고 후 허용(두 전이 모두 적용).
ARTIFACT_DIR=packer/dist VERSION=vX.Y.Z ./tools/release-promote.sh promote

# staging에서 실제 provider/architecture/filesystem smoke test 수행 후 verification.json 갱신

# 2단계: staging -> production (매트릭스 전 항목 PASS 필요, 위 evidence 게이트 동일 적용)
ARTIFACT_DIR=packer/dist VERSION=vX.Y.Z ./tools/release-promote.sh promote
```

매 전이는 `release-evidence/$VERSION/promotion-log.tsv`에 (timestamp, from_stage, to_stage) 한 줄로 기록된다. production은 종착 stage이며, 여기서 다시 `promote`를 실행하면 거부된다.

언제든 아래로 현재 상태를 점검할 수 있다:

```bash
# SHA256SUMS 에 나열된 .box 가 있는 디렉터리를 ARTIFACT_DIR 로 지정한다.
ARTIFACT_DIR=packer/dist VERSION=vX.Y.Z ./tools/release-promote.sh verify
```

`verify`는 stage=candidate에서는 evidence 준비 상태만 보고하고(부족해도 exit 0), stage=staging/production에서는 evidence가 없거나 무효하면 반드시 실패(exit 1)한다. `verification.json`과 required-matrix 계약은 [release-evidence/README.md](../release-evidence/README.md)를 참고.

## 4. GitHub Release + Pages 카탈로그 게시

> `upload-boxes.sh`, `nixos/upload-nixos.sh`, `packer/scripts/upload-all.sh`, CI의 `Publish to Vagrant Cloud` 단계는 폐기되었다 (HCP Vagrant가 신규 버전 생성을 차단). 사용하지 않는다.

검증 완료된 provider만 `.box`를 GitHub Release 자산으로 올리고, `site/boxes/<box-name>.json` 카탈로그를 재생성해 Pages로 배포한다. 절차와 체크섬 규칙은 [box-distribution.md](box-distribution.md)를 따른다.

이미 공개된 버전은 덮어쓰거나 삭제하지 않는다. 새 빌드는 새 immutable version으로 발행한다.

## 5. 배포 후 검증

```bash
mkdir test-download && cd test-download
vagrant init dasomel/ubuntu-24.04-ext4 \
  https://dasomel.github.io/kube-ready-box/boxes/ubuntu-24.04-ext4.json
vagrant up --provider=vmware_desktop
vagrant ssh -c "uname -a"
vagrant ssh -c "cat /etc/vagrant-box/info.txt"
vagrant destroy -f
```

## 6. Rollback

문제 발생 시 이전 정상 버전을 pin한다. GitHub Release 자산이나 Git tag를 삭제하지 않는다.

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
