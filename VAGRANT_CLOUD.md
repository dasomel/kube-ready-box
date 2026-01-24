# Vagrant Cloud 배포/관리 가이드

Vagrant Cloud에 box를 업로드, 관리, 삭제하는 방법을 설명합니다.

## 목차

- [Box 전략](#box-전략)
- [사전 준비](#사전-준비)
- [Box 업로드](#box-업로드)
  - [수동 업로드 (ARM64)](#수동-업로드-arm64)
  - [자동 업로드 (GitHub Actions)](#자동-업로드-github-actions)
- [Provider 관리](#provider-관리)
- [Version 관리](#version-관리)
- [삭제 작업](#삭제-작업)
- [문제 해결](#문제-해결)

---

## Box 전략

**통합 Multi-Architecture Box**: `dasomel/ubuntu-24.04`

하나의 box에 모든 provider와 architecture를 포함하는 전략을 사용합니다:

| Architecture | VirtualBox | VMware Fusion |
|--------------|------------|---------------|
| **AMD64** | ✅ GitHub Actions | ✅ GitHub Actions |
| **ARM64** | ✅ 수동 업로드 | ✅ 수동 업로드 |

**장점**:
- 사용자가 `vagrant init dasomel/ubuntu-24.04` 하나로 모든 환경 지원
- Vagrant가 자동으로 호스트 아키텍처와 provider에 맞는 box 선택
- 단일 box 관리로 버전 관리 간소화

**사용 방법**:
```bash
# 모든 환경에서 동일한 명령어
vagrant init dasomel/ubuntu-24.04
vagrant up  # 자동으로 적절한 provider/architecture 선택
```

---

## 사전 준비

### 1. Vagrant Cloud 로그인

```bash
# 1. Vagrant Cloud 웹에서 토큰 발행
# https://app.vagrantup.com/settings/security

# 2. CLI 로그인
vagrant cloud auth login --token YOUR_VAGRANT_CLOUD_TOKEN

# 3. 로그인 확인
vagrant cloud auth whoami
```

### 2. Box 파일 확인

```bash
cd /Users/m/Documents/IdeaProjects/kube-ready-box/packer/output-vagrant
ls -lh *.box

# 예상 출력:
# ubuntu-24.04-vmware-arm64.box      (2.3GB)
# ubuntu-24.04-virtualbox-arm64.box  (2.3GB)
# ubuntu-24.04-vmware-amd64.box      (2.3GB)
# ubuntu-24.04-virtualbox-amd64.box  (2.3GB)
```

---

## Box 업로드

### 수동 업로드 (ARM64)

ARM64 box는 Apple Silicon Mac에서 수동으로 빌드하고 업로드합니다.

#### 방법 1: 자동 스크립트 사용 (권장)

```bash
# 프로젝트 루트에서 실행
cd /Users/m/Documents/IdeaProjects/kube-ready-box
bash upload-boxes.sh
```

스크립트가 자동으로:
- 로그인 상태 확인
- VMware provider 업로드 (또는 건너뛰기)
- VirtualBox provider 업로드
- 업로드 완료 확인

### 방법 2: 수동 명령어 실행

#### 첫 번째 Provider 업로드 (새 버전 생성)

```bash
cd packer/output-vagrant

# VMware provider 업로드 (새 버전 v0.1.0 생성)
vagrant cloud publish dasomel/ubuntu-24.04 0.1.0 vmware_desktop \
  ubuntu-24.04-vmware-arm64.box \
  --architecture arm64 \
  --version-description "Initial release - Kubernetes-ready Ubuntu 24.04 LTS

## Features
- Ubuntu 24.04 LTS with OS optimizations
- Multi-architecture support (AMD64, ARM64)
- Multi-provider support (VirtualBox, VMware)
- Kubernetes prerequisites configured

## Documentation
https://github.com/dasomel/kube-ready-box" \
  --release \
  --short-description "Kubernetes-ready Ubuntu 24.04 LTS Vagrant Box"
```

#### 기존 버전에 Provider 추가

```bash
# 1. Provider 생성
vagrant cloud provider create dasomel/ubuntu-24.04 0.1.0 virtualbox \
  --architecture arm64

# 2. Box 파일 업로드
vagrant cloud provider upload dasomel/ubuntu-24.04 0.1.0 virtualbox \
  arm64 ubuntu-24.04-virtualbox-arm64.box
```

---

### 자동 업로드 (GitHub Actions)

AMD64 box는 GitHub Actions를 통해 자동으로 빌드 및 업로드됩니다.

#### 사전 설정

1. **GitHub Secrets 설정**
   ```bash
   # Repository Settings > Secrets and variables > Actions
   # New repository secret 추가:
   # Name: VAGRANT_CLOUD_TOKEN
   # Value: <your_vagrant_cloud_token>
   ```

2. **Workflow 파일 위치**
   - `.github/workflows/build-amd64.yml` - AMD64 자동 빌드/배포
   - `.github/workflows/build-arm64.yml` - ARM64 자동 빌드/배포 (self-hosted runner 필요)

#### AMD64 자동 배포

**트리거 방법**:

1. **Tag 기반 자동 배포** (권장)
   ```bash
   git tag v1.0.1
   git push origin v1.0.1
   ```
   - 자동으로 빌드 및 Vagrant Cloud 업로드
   - 버전: tag에서 자동 추출 (v1.0.1 → 1.0.1)

2. **수동 트리거**
   ```bash
   # GitHub 웹에서:
   # Actions > Build AMD64 Vagrant Boxes > Run workflow
   # - version: 1.0.1 (선택)
   # - publish: true (체크)
   ```

#### Workflow 동작 방식

**AMD64 Workflow** (build-amd64.yml):
```yaml
1. VirtualBox 설치 (ubuntu-latest runner)
2. Packer로 VirtualBox AMD64 box 빌드
3. 버전 존재 확인:
   - 신규 버전: vagrant cloud publish (버전 생성)
   - 기존 버전: provider create + upload (provider 추가)
4. --architecture amd64 태그 자동 추가
```

**ARM64 Workflow** (build-arm64.yml):
```yaml
1. VMware/VirtualBox 검증 (self-hosted macOS ARM64 runner)
2. Packer로 box 빌드
3. 버전 존재 확인:
   - 신규 버전: vagrant cloud publish (VMware 또는 VirtualBox)
   - 기존 버전: provider create + upload
4. --architecture arm64 태그 자동 추가
```

#### 배포 순서 (권장)

통합 box에 모든 provider/architecture를 추가하는 순서:

```bash
# 1. ARM64 수동 업로드 (최초 버전 생성)
bash upload-boxes.sh  # VMware/VirtualBox ARM64 업로드

# 2. GitHub에 tag push (AMD64 자동 배포)
git tag v0.1.0
git push origin v0.1.0  # Actions가 자동으로 AMD64 추가

# 최종 결과:
# dasomel/ubuntu-24.04 v0.1.0
#   - vmware_desktop (arm64) ✅
#   - virtualbox (arm64) ✅
#   - vmware_desktop (amd64) ✅ (추가 예정)
#   - virtualbox (amd64) ✅
```

#### Actions 로그 확인

```bash
# GitHub 웹에서:
# Actions > 해당 workflow run 클릭 > 로그 확인

# 성공 확인:
vagrant cloud search dasomel/ubuntu-24.04 --json | python3 -m json.tool
```

---

### 업로드 확인

```bash
# Box 정보 조회
vagrant cloud box show dasomel/ubuntu-24.04

# Provider 목록 확인
vagrant cloud search dasomel/ubuntu-24.04 --json | python3 -m json.tool

# 웹 브라우저에서 확인
# https://app.vagrantup.com/dasomel/boxes/ubuntu-24.04
```

---

## Provider 관리

### Provider 목록 조회

```bash
vagrant cloud search dasomel/ubuntu-24.04 --json | python3 -m json.tool
```

### Provider 추가

```bash
# AMD64 아키텍처 추가 예시
vagrant cloud provider create dasomel/ubuntu-24.04 0.1.0 vmware_desktop \
  --architecture amd64

vagrant cloud provider upload dasomel/ubuntu-24.04 0.1.0 vmware_desktop \
  amd64 ubuntu-24.04-vmware-amd64.box
```

### Provider 삭제

```bash
# 특정 provider 삭제
vagrant cloud provider delete dasomel/ubuntu-24.04 vmware_desktop 0.1.0 arm64 --force

# 예시:
# - VMware ARM64만 삭제
vagrant cloud provider delete dasomel/ubuntu-24.04 vmware_desktop 0.1.0 arm64 --force

# - VirtualBox AMD64만 삭제
vagrant cloud provider delete dasomel/ubuntu-24.04 virtualbox 0.1.0 amd64 --force
```

---

## Version 관리

### 새 버전 생성

```bash
# v1.1.0 생성 및 업로드
vagrant cloud publish dasomel/ubuntu-24.04 1.1.0 vmware_desktop \
  ubuntu-24.04-vmware-arm64.box \
  --architecture arm64 \
  --version-description "Version 1.1.0 release notes..." \
  --release
```

### 버전 목록 조회

```bash
vagrant cloud box show dasomel/ubuntu-24.04
```

### 버전 릴리즈/취소

```bash
# 버전 릴리즈 (공개)
vagrant cloud version release dasomel/ubuntu-24.04 0.1.0

# 버전 취소 (비공개로 전환)
vagrant cloud version revoke dasomel/ubuntu-24.04 0.1.0
```

### 버전 설명 업데이트

```bash
vagrant cloud version update dasomel/ubuntu-24.04 0.1.0 \
  --version-description "Updated description..."
```

---

## 삭제 작업

### 1. 특정 Provider만 삭제

**용도**: 잘못 업로드된 provider만 삭제하고 다시 올릴 때

```bash
# VMware ARM64 provider만 삭제
vagrant cloud provider delete dasomel/ubuntu-24.04 vmware_desktop 0.1.0 arm64 --force

# 삭제 후 다시 업로드
vagrant cloud provider create dasomel/ubuntu-24.04 0.1.0 vmware_desktop --architecture arm64
vagrant cloud provider upload dasomel/ubuntu-24.04 0.1.0 vmware_desktop arm64 ubuntu-24.04-vmware-arm64.box
```

### 2. 특정 버전 삭제

**용도**: v0.1.0 전체를 삭제하고 처음부터 다시 업로드할 때

```bash
# v0.1.0 전체 삭제 (모든 provider 포함)
vagrant cloud version delete dasomel/ubuntu-24.04 0.1.0 --force

# 삭제 확인
vagrant cloud box show dasomel/ubuntu-24.04
```

**주의**: 이 명령은 해당 버전의 모든 provider (vmware_desktop, virtualbox, 모든 아키텍처)를 삭제합니다.

### 3. Box 전체 삭제

**용도**: Box를 완전히 삭제하고 새로 시작할 때

```bash
# dasomel/ubuntu-24.04 전체 삭제 (모든 버전, 모든 provider)
vagrant cloud box delete dasomel/ubuntu-24.04 --force
```

**경고**: 이 명령은 복구 불가능합니다. 신중하게 사용하세요.

---

## 문제 해결

### 1. TTY Error 발생

**문제**:
```
Vagrant is attempting to interface with the UI in a way that requires a TTY
```

**해결**:
- Claude Code 터미널이 아닌 실제 Terminal.app 사용
- `--force` 또는 `--no-tty` 플래그 추가
- Token 기반 로그인 사용: `vagrant cloud auth login --token YOUR_TOKEN`

### 2. Provider Already Exists

**문제**:
```
Provider already exists
```

**해결**:
```bash
# 에러 무시하고 계속 진행
vagrant cloud provider create ... 2>/dev/null || true

# 또는 기존 provider 삭제 후 다시 생성
vagrant cloud provider delete ... --force
vagrant cloud provider create ...
```

### 3. 업로드 중단/실패

**문제**: 대용량 파일 (2.3GB) 업로드 중 네트워크 끊김

**해결**:
```bash
# 1. 현재 상태 확인
vagrant cloud search dasomel/ubuntu-24.04 --json | python3 -m json.tool

# 2. 실패한 provider 삭제
vagrant cloud provider delete dasomel/ubuntu-24.04 PROVIDER VERSION ARCH --force

# 3. 다시 업로드
vagrant cloud provider create ...
vagrant cloud provider upload ...
```

### 4. Version Not Released

**문제**: 버전이 생성되었지만 public으로 보이지 않음

**해결**:
```bash
# 버전 릴리즈
vagrant cloud version release dasomel/ubuntu-24.04 0.1.0

# 릴리즈 상태 확인
vagrant cloud box show dasomel/ubuntu-24.04
```

### 5. 로그인 만료

**문제**: 업로드 중 인증 에러

**해결**:
```bash
# 현재 로그인 상태 확인
vagrant cloud auth whoami

# 재로그인
vagrant cloud auth login --token YOUR_TOKEN
```

---

## 유용한 명령어

### Box 정보 조회

```bash
# 간단한 정보
vagrant cloud box show dasomel/ubuntu-24.04

# 상세 정보 (JSON)
vagrant cloud search dasomel/ubuntu-24.04 --json | python3 -m json.tool

# 다운로드 통계
# 웹 브라우저: https://app.vagrantup.com/dasomel/boxes/ubuntu-24.04/versions/0.1.0
```

### 로컬 테스트

```bash
# Vagrant Cloud 업로드 전 로컬 테스트
cd test-vm
vagrant box add test/ubuntu-24.04 ../packer/output-vagrant/ubuntu-24.04-vmware-arm64.box --force
vagrant up
vagrant ssh
```

### Box 파일 크기 확인

```bash
ls -lh packer/output-vagrant/*.box | awk '{print $9, $5}'
```

---

## 배포 체크리스트

업로드 전 확인 사항:

- [ ] Box 파일 빌드 완료 (`packer build` 성공)
- [ ] 로컬 테스트 완료 (`vagrant up` 성공)
- [ ] Vagrant Cloud 로그인 완료
- [ ] 버전 번호 확인 (CHANGELOG.md 참고)
- [ ] GitHub Release 생성 완료
- [ ] version-description 내용 최신화
- [ ] Box 파일 크기 확인 (2-3GB)

업로드 후 확인 사항:

- [ ] Vagrant Cloud에서 provider 확인
- [ ] Architecture 태그 확인 (arm64, amd64)
- [ ] Version released 상태 확인
- [ ] 다운로드 테스트: `vagrant init dasomel/ubuntu-24.04 && vagrant up`
- [ ] README.md의 Vagrant Cloud 링크 업데이트
- [ ] 다운로드 통계 모니터링

---

## 참고 링크

- **Vagrant Cloud CLI 문서**: https://developer.hashicorp.com/vagrant/cloud-docs/cli
- **Box URL**: https://app.vagrantup.com/dasomel/boxes/ubuntu-24.04
- **Token 관리**: https://app.vagrantup.com/settings/security
- **프로젝트 GitHub**: https://github.com/dasomel/kube-ready-box

---

## 빠른 참조

### 전체 재업로드 (v0.1.0 삭제 후 다시)

```bash
# 1. 기존 버전 삭제
vagrant cloud version delete dasomel/ubuntu-24.04 0.1.0 --force

# 2. 재업로드
cd /Users/m/Documents/IdeaProjects/kube-ready-box
bash upload-boxes.sh
```

### 특정 Provider만 추가

```bash
cd packer/output-vagrant

# VirtualBox ARM64 추가
vagrant cloud provider create dasomel/ubuntu-24.04 0.1.0 virtualbox --architecture arm64
vagrant cloud provider upload dasomel/ubuntu-24.04 0.1.0 virtualbox arm64 ubuntu-24.04-virtualbox-arm64.box

# VMware AMD64 추가
vagrant cloud provider create dasomel/ubuntu-24.04 0.1.0 vmware_desktop --architecture amd64
vagrant cloud provider upload dasomel/ubuntu-24.04 0.1.0 vmware_desktop amd64 ubuntu-24.04-vmware-amd64.box
```

### 로그인 상태 확인

```bash
vagrant cloud auth whoami || echo "Not logged in"
```
