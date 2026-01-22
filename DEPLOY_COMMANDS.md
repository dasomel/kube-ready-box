# 배포 명령어 모음

배포를 실행할 때 이 파일의 명령어를 순서대로 복사해서 사용하세요.

## 사전 준비

1. GitHub에서 리포지토리 생성: https://github.com/new
   - Repository name: `kube-ready-box`
   - Public
   - MIT License

2. Vagrant Cloud 로그인 준비
   - https://app.vagrantup.com/settings/security
   - Token 생성

---

## 단계 1: Git 초기 커밋

```bash
cd /Users/m/Documents/IdeaProjects/kube-ready-box

# 모든 파일 staging
git add -A

# 초기 커밋
git commit -m "Initial release: dasomel/ubuntu-24.04 v1.0.0

Features:
- Ubuntu 24.04 LTS base
- K8s-ready OS optimizations
- Multi-architecture (AMD64/ARM64)
- Multi-provider (VirtualBox/VMware)
- MIT License
- SBOM included
- Comprehensive documentation
- CHANGELOG.md for version tracking

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"

# Remote 추가
git remote add origin https://github.com/dasomel/kube-ready-box.git

# Main 브랜치로 푸시
git push -u origin main

# 릴리즈 태그 생성
git tag -a v1.0.0 -m "Release v1.0.0"

# 태그 푸시
git push origin v1.0.0
```

---

## 단계 2: GitHub Release 생성

### 방법 1: GitHub CLI

```bash
# CHANGELOG에서 릴리즈 노트 추출
gh release create v1.0.0 \
  --title "v1.0.0 - Initial Release" \
  --notes-file <(sed -n '/## \[1.0.0\]/,/## \[0.9.0\]/p' CHANGELOG.md | head -n -2)
```

### 방법 2: 웹 UI

1. https://github.com/dasomel/kube-ready-box/releases/new
2. Tag: `v1.0.0`
3. Release title: `v1.0.0 - Initial Release`
4. Description: CHANGELOG.md의 `[1.0.0]` 섹션 복사

---

## 단계 3: Vagrant Cloud 설정

### 로그인

```bash
# Vagrant Cloud 로그인
vagrant cloud auth login
# Username: dasomel
# Password: [your-password]

# 또는 Token 사용
export VAGRANT_CLOUD_TOKEN='your-token-here'
```

### Box 생성 (웹 UI)

https://app.vagrantup.com/boxes/new

- Username: `dasomel` (자동)
- Box name: `ubuntu-24.04`
- Short description: `Kubernetes-ready Ubuntu 24.04 LTS Vagrant Box`
- Description:
```markdown
OS-level optimized Ubuntu 24.04 LTS for Kubernetes workloads.

## Features
- Multi-architecture: AMD64, ARM64
- Multi-provider: VirtualBox, VMware Fusion
- K8s prerequisites pre-configured
- Network, disk, memory optimizations
- MIT License

## Documentation
https://github.com/dasomel/kube-ready-box

## Quick Start
\`\`\`bash
vagrant init dasomel/ubuntu-24.04
vagrant up
\`\`\`
```
- Visibility: Public

---

## 단계 4: Box 파일 업로드

```bash
cd packer/output-vagrant

# VMware ARM64 업로드
vagrant cloud publish dasomel/ubuntu-24.04 1.0.0 vmware_desktop \
  ubuntu-24.04-vmware-arm64.box \
  --architecture arm64 \
  --version-description "Initial release - K8s ready Ubuntu 24.04 LTS

## What's New
- Ubuntu 24.04 LTS base with cloud-init
- Multi-architecture support (AMD64, ARM64)
- Multi-provider support (VirtualBox, VMware)
- Comprehensive OS optimizations for K8s
- MIT License with SBOM

## Documentation
https://github.com/dasomel/kube-ready-box

See CHANGELOG: https://github.com/dasomel/kube-ready-box/blob/main/CHANGELOG.md" \
  --release

# VirtualBox ARM64 업로드
vagrant cloud version provider create dasomel/ubuntu-24.04 1.0.0 virtualbox \
  --architecture arm64

vagrant cloud version provider upload dasomel/ubuntu-24.04 1.0.0 virtualbox \
  arm64 ubuntu-24.04-virtualbox-arm64.box

cd ../..
```

---

## 단계 5: GitHub Actions Secrets 설정

https://github.com/dasomel/kube-ready-box/settings/secrets/actions

1. [New repository secret] 클릭
2. Name: `VAGRANT_CLOUD_TOKEN`
3. Value: (Vagrant Cloud Token)
4. [Add secret] 클릭

---

## 단계 6: GitHub Actions AMD64 빌드 트리거

```bash
# 태그 푸시로 자동 트리거 (이미 완료)
# git push origin v1.0.0

# 또는 수동 트리거
gh workflow run build-amd64.yml

# 워크플로우 상태 확인
gh run list --workflow=build-amd64.yml
```

---

## 단계 7: 배포 검증

```bash
# 새 디렉토리에서 테스트
mkdir -p ~/test-kube-ready-box && cd ~/test-kube-ready-box

# Vagrantfile 생성
vagrant init dasomel/ubuntu-24.04

# VMware로 실행
vagrant up --provider=vmware_desktop

# 검증
vagrant ssh -c "uname -a"
vagrant ssh -c "cat /etc/vagrant-box/info.txt"
vagrant ssh -c "/bin/bash /etc/vagrant-box/check-tuning.sh"

# 정리
vagrant destroy -f
cd ~ && rm -rf ~/test-kube-ready-box
```

---

## 단계 8: GitHub 프로젝트 설정

### About 설정

https://github.com/dasomel/kube-ready-box (우측 상단 설정 아이콘)

- Description: `Kubernetes-ready Ubuntu 24.04 LTS Vagrant Box`
- Website: `https://app.vagrantup.com/dasomel/boxes/ubuntu-24.04`
- Topics: `vagrant`, `kubernetes`, `ubuntu`, `packer`, `k8s`, `ubuntu-24-04`, `containerd`, `linux`

### README 배지 확인

- License 배지 작동 확인
- Vagrant Cloud 배지 작동 확인

---

## 단계 9: 커뮤니티 공지 (선택)

### HashiCorp Discuss

https://discuss.hashicorp.com/c/vagrant/24

제목: `[Announce] dasomel/ubuntu-24.04 - K8s-ready Vagrant Box`

### Reddit r/vagrant

https://www.reddit.com/r/vagrant/

제목: `New Vagrant Box: Kubernetes-ready Ubuntu 24.04 LTS`

---

## 롤백 (문제 발생 시)

```bash
# Vagrant Cloud에서 버전 삭제
vagrant cloud version delete dasomel/ubuntu-24.04 1.0.0

# GitHub Release 삭제
gh release delete v1.0.0 --yes

# GitHub 태그 삭제
git tag -d v1.0.0
git push origin :refs/tags/v1.0.0

# Git 커밋 되돌리기 (주의!)
git reset --hard HEAD~1
git push origin main --force
```

---

## 배포 완료 확인

```bash
# Vagrant Cloud에서 확인
curl -s https://app.vagrantup.com/api/v1/box/dasomel/ubuntu-24.04 | jq .

# Box 버전 확인
vagrant box list | grep ubuntu-24.04

# GitHub Release 확인
gh release view v1.0.0
```

---

## 다음 릴리즈 (v1.1.0)

1. CHANGELOG.md 업데이트
2. `git commit -am "Release v1.1.0"`
3. `git tag -a v1.1.0 -m "Release v1.1.0"`
4. `git push origin v1.1.0`
5. Vagrant Cloud에 새 버전 업로드
