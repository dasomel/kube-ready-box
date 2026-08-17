# 배포 체크리스트

## 1. 로컬 빌드 및 테스트

```bash
cd packer

# Packer 초기화
./build.sh init

# 템플릿 검증
./build.sh validate

# 현재 플랫폼에 맞는 box 빌드
./build.sh vmware-arm64  # Apple Silicon
# 또는
./build.sh virtualbox-amd64  # Intel Mac

# 로컬 테스트
vagrant box add --name test/ubuntu-24.04-ext4 output-vagrant/ubuntu-24.04-ext4-*.box
cd ../test-vm/vmware  # 또는 virtualbox
vagrant up
./verify_box.sh
vagrant destroy -f
vagrant box remove test/ubuntu-24.04-ext4
```

## 2. Git 커밋 및 푸시

```bash
cd /Users/m/Documents/IdeaProjects/kube-ready-box

# 커밋 (버전 맞춤)
git add -A
git commit -m "Release: kube-ready-box v{VERSION}

{RELEASE_NOTES}

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"

# GitHub에 푸시
git push -u origin main

# 릴리스 태그
git tag -a v{VERSION} -m "Release v{VERSION}"
git push origin v{VERSION}
```

## 3. Vagrant Cloud 업로드

### 3.1 Vagrant Cloud 계정 설정

```bash
# Vagrant Cloud 로그인
vagrant cloud auth login
```

### 3.2 Box 생성 (최초 1회)

Vagrant Cloud 웹사이트에서:
1. https://app.vagrantup.com/ 접속
2. "Create a new Vagrant Box" 클릭
3. Box name: `dasomel/ubuntu-24.04-ext4` (또는 `ubuntu-24.04-xfs`)
4. Short description: "Kubernetes-ready Ubuntu 24.04 LTS Vagrant Box (ext4)" (또는 "(xfs)")
5. License: MIT

### 3.3 Box 버전 업로드

```bash
# 검증 완료된 provider만 명시적으로 업로드 (오발행 방지)
PROVIDERS=vmware_desktop UBUNTU_VERSION=24.04 VERSION={VERSION} ./upload-boxes.sh
```

## 4. GitHub Actions로 AMD64 빌드

1. GitHub Actions Secrets 설정:
   - `VAGRANT_CLOUD_TOKEN`: Vagrant Cloud API token

2. AMD64 빌드 트리거:
```bash
# 태그 푸시로 자동 트리거
git push origin v{VERSION}

# 또는 수동 트리거
gh workflow run build-amd64.yml
```

## 5. 배포 후 검증

```bash
# Vagrant Cloud에서 다운로드 테스트
mkdir test-download && cd test-download
vagrant init dasomel/ubuntu-24.04-ext4
vagrant up --provider=vmware_desktop
vagrant ssh -c "uname -a"
vagrant ssh -c "cat /etc/vagrant-box/info.txt"
vagrant destroy -f
cd .. && rm -rf test-download
```

## 6. GitHub Release 생성

```bash
# CHANGELOG에서 버전 섹션 추출하여 Release 생성
gh release create v{VERSION} \
  --title "v{VERSION} - {RELEASE_TITLE}" \
  --notes-file <(sed -n '/## \[{VERSION}\]/,/## \[/p' CHANGELOG.md | head -n -2)

# 또는 웹 UI에서 생성:
# 1. https://github.com/dasomel/kube-ready-box/releases/new
# 2. Tag: v{VERSION}
# 3. Release title: v{VERSION} - {RELEASE_TITLE}
# 4. Description: CHANGELOG.md의 해당 버전 섹션 복사
# 5. Attach SBOM files (box에서 추출)
```

## 7. 문서 업데이트

- [ ] GitHub Release 생성 및 CHANGELOG 포함
- [ ] GitHub Release에 SBOM 첨부
- [ ] README.md에 Vagrant Cloud 링크 확인
- [ ] GitHub Topics 설정: `vagrant`, `kubernetes`, `ubuntu`, `packer`, `k8s`
- [ ] GitHub About 설정: Description, Website, Topics
- [ ] CHANGELOG.md 날짜 확인

## 8. 커뮤니티 공지 (선택)

- [ ] HashiCorp Discuss (https://discuss.hashicorp.com/)
- [ ] Reddit r/vagrant
- [ ] 개인 블로그/SNS

---

## 롤백 절차

문제 발생 시:

```bash
# Vagrant Cloud에서 버전 삭제
vagrant cloud version delete dasomel/ubuntu-24.04-ext4 {VERSION}
vagrant cloud version delete dasomel/ubuntu-24.04-xfs {VERSION}

# GitHub 태그 삭제
git tag -d v{VERSION}
git push origin :refs/tags/v{VERSION}
```
