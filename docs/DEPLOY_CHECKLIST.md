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

```bash
# 모든 evidence가 준비된 후
VERSION=vX.Y.Z ./tools/release-promote.sh promote
```

staging에서 실제 provider/architecture/filesystem smoke test를 완료하고 모든 matrix가 PASS인 경우에만 production으로 승격한다.

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

```bash
VERSION=vX.Y.Z PREVIOUS_VERSION=vX.Y.Z-previous ./tools/release-promote.sh rollback
```

rollback 결과는 `release-evidence/rollback/rollback-pin.env`에 기록한다.

## 7. GitHub Release

```bash
gh release create vX.Y.Z --title "vX.Y.Z - RELEASE_TITLE"
```

GitHub Release에는 CHANGELOG와 SBOM/security/license evidence를 연결한다.
