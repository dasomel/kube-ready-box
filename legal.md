# OSS 라이선스 및 법적 검토

> **참고**: 이 문서는 kube-ready-box (`dasomel/ubuntu-24.04`)를 공개 배포할 때 필요한 라이선스, SBOM, 법적 검토 사항을 다룹니다.

## 1. 라이선스 선택 가이드

| 라이선스 | 특징 | 권장 용도 |
|----------|------|-----------|
| MIT | 가장 관대, 상업적 사용 가능 | 제한 없이 자유롭게 사용 허용 |
| Apache 2.0 | 특허권 보호, 변경 사항 명시 | 기업 친화적, 특허 보호 필요 시 |
| GPL 3.0 | Copyleft, 파생물도 공개 필수 | 오픈소스 생태계 기여 강조 |

---

## 2. 프로젝트 구조에 라이선스 포함

```
project/
├── LICENSE                 # 라이선스 전문
├── NOTICE                  # 저작권 및 서드파티 고지
├── README.md               # 라이선스 배지 포함
├── packer/
│   └── scripts/
│       └── license-info.sh # Box 내 라이선스 정보 설치
└── ...
```

---

## 3. LICENSE 파일 (MIT 예시)

```
MIT License

Copyright (c) 2024 dasomel

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## 4. NOTICE 파일 (서드파티 고지)

```
dasomel/ubuntu-24.04 Vagrant Box
Copyright (c) 2024 dasomel

This product includes software developed by:

- Ubuntu (https://ubuntu.com/) - Licensed under various open source licenses
- Kubernetes (https://kubernetes.io/) - Apache License 2.0
- containerd (https://containerd.io/) - Apache License 2.0
- Packer (https://packer.io/) - MPL 2.0
- Vagrant (https://vagrantup.com/) - BUSL 1.1

Third-party licenses can be found in /usr/share/doc/ within the box.
```

---

## 5. Box 내 라이선스 정보 설치

### scripts/license-info.sh

```bash
#!/bin/bash
set -e

# 라이선스 정보 디렉토리 생성
sudo mkdir -p /etc/vagrant-box

# Box 메타 정보
cat <<EOF | sudo tee /etc/vagrant-box/info.json
{
  "name": "ubuntu-24.04",
  "version": "1.0.0",
  "license": "MIT",
  "author": "dasomel",
  "homepage": "https://github.com/dasomel/ubuntu-24.04",
  "build_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

# 라이선스 파일 복사
cat <<'EOF' | sudo tee /etc/vagrant-box/LICENSE
MIT License

Copyright (c) 2024 dasomel
...
EOF

# MOTD에 라이선스 정보 추가
cat <<'EOF' | sudo tee /etc/update-motd.d/99-vagrant-box
#!/bin/bash
echo ""
echo "dasomel/ubuntu-24.04 - MIT License"
echo "https://github.com/dasomel/ubuntu-24.04"
echo ""
EOF
sudo chmod +x /etc/update-motd.d/99-vagrant-box
```

---

## 6. README.md 라이선스 배지

```markdown
# dasomel/ubuntu-24.04

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Vagrant Cloud](https://img.shields.io/badge/Vagrant-Cloud-blue)](https://app.vagrantup.com/dasomel/boxes/ubuntu-24.04)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

### Third-party Licenses

This box includes the following open source software:

| Software | License |
|----------|---------|
| Ubuntu 24.04 | [Various](https://ubuntu.com/legal/open-source-licences) |
| Kubernetes | Apache 2.0 |
| containerd | Apache 2.0 |
| Flannel | Apache 2.0 |
```

---

## 7. Vagrant Cloud 업로드 시 라이선스 명시

```bash
# Box 설명에 라이선스 포함
vagrant cloud publish dasomel/ubuntu-24.04 1.0.0 \
  virtualbox ./ubuntu-24.04-virtualbox-amd64.box \
  --architecture amd64 \
  --description "$(cat <<'EOF'
Kubernetes-ready Ubuntu 24.04 Vagrant Box

## License
MIT License - Free for personal and commercial use

## Features
- Ubuntu 24.04 LTS Cloud Image 기반
- K8s 설치를 위한 OS 최적화 (커널 튜닝, sysctl 등)
- K8s 미포함 (사용자가 원하는 버전 설치)

See https://github.com/dasomel/ubuntu-24.04 for full details.
EOF
)" \
  --release
```

---

## 8. 배포 전 법적 검토 사항

Public 배포 시 문제가 될 수 있는 항목들을 사전에 검토해야 합니다.

### 8.1 라이선스 호환성 검토

```bash
# GPL 라이선스 패키지 확인 (Copyleft 주의)
dpkg-query -W -f='${Package}\n' | xargs -I {} sh -c \
  'apt-cache show {} 2>/dev/null | grep -q "GPL" && echo {}'

# 비상업용 라이선스 패키지 확인
apt-cache show <package> | grep -iE "non-commercial|personal use only"
```

| 위험 수준 | 라이선스 | 주의사항 |
|----------|----------|----------|
| 높음 | AGPL | 네트워크 사용 시에도 소스 공개 필수 |
| 높음 | GPL | 파생물 전체 GPL 적용, 소스 공개 필수 |
| 중간 | LGPL | 동적 링크 시 분리 가능, 수정 시 공개 |
| 낮음 | Apache/MIT/BSD | 상업적 사용 자유, 고지 의무만 있음 |

### 8.2 상표권 (Trademark) 검토

- [ ] Ubuntu 로고/이름 사용 시 [Canonical 상표 정책](https://ubuntu.com/legal/trademarks) 준수
- [ ] Kubernetes 로고 사용 시 [CNCF 상표 가이드라인](https://www.cncf.io/brand-guidelines/) 확인
- [ ] "Official" 또는 공식 배포로 오해할 수 있는 표현 금지
- [ ] Box 이름에 상표 직접 사용 주의 (예: `kubernetes-box` → `k8s-ready-box`)

### 8.3 특허권 검토

- [ ] 코덱, 암호화 알고리즘 특허 확인 (예: H.264, AAC)
- [ ] 소프트웨어 특허 관련 조항이 있는 라이선스 확인 (Apache 2.0 특허 조항)

### 8.4 수출 규제 검토

```bash
# 암호화 관련 패키지 확인
dpkg -l | grep -iE "openssl|crypto|gnupg"
```

- [ ] 암호화 소프트웨어 포함 시 수출 규정 확인 (미국 EAR, 한국 전략물자)
- [ ] 특정 국가 제한이 있는 소프트웨어 확인

### 8.5 개인정보 및 보안 검토

```bash
# Box 내 민감 정보 확인
grep -rn "password\|secret\|api_key\|token" /etc/
find / -name "*.pem" -o -name "*.key" 2>/dev/null

# SSH 키 확인 (삭제 필수)
ls -la /home/*/.ssh/
ls -la /root/.ssh/
```

- [ ] 하드코딩된 비밀번호, API 키 제거
- [ ] 빌드 시 생성된 SSH 키 삭제
- [ ] 로그 파일 정리 (`/var/log/*`)
- [ ] bash history 삭제 (`~/.bash_history`)
- [ ] 개인 식별 정보 제거

### 8.6 재배포 제한 확인

| 소프트웨어 | 재배포 가능 여부 | 비고 |
|------------|------------------|------|
| Ubuntu | O | 상표 사용 시 정책 준수 |
| VMware Tools | 조건부 | VMware 약관 확인 필요 |
| VirtualBox GA | O | GPL v2 |
| 상용 소프트웨어 | X | 절대 포함 금지 |

---

## 9. 문제 패키지 자동 검사 스크립트

### scripts/license-audit.sh

```bash
#!/bin/bash
# scripts/license-audit.sh

echo "=== License Audit Report ==="

echo -e "\n[1] GPL/AGPL 패키지 (Copyleft 주의)"
dpkg-query -W -f='${Package}\n' | while read pkg; do
  license=$(apt-cache show "$pkg" 2>/dev/null | grep -i "^License:" | head -1)
  if echo "$license" | grep -qiE "GPL|AGPL"; then
    echo "  - $pkg: $license"
  fi
done

echo -e "\n[2] 비자유 소프트웨어 (non-free)"
grep -r "non-free\|contrib" /etc/apt/sources.list* 2>/dev/null

echo -e "\n[3] 민감 파일 검사"
find /etc /home /root -name "*.key" -o -name "*.pem" -o -name "*password*" 2>/dev/null

echo -e "\n[4] SSH 키 확인"
find /home /root -name "id_rsa*" -o -name "id_ed25519*" 2>/dev/null

echo -e "\n[5] 하드코딩된 시크릿"
grep -rn --include="*.sh" --include="*.conf" "password=\|secret=\|api_key=" /etc/ 2>/dev/null | head -20

echo -e "\n=== Audit Complete ==="
```

---

## 10. 정리 스크립트

### scripts/cleanup.sh

```bash
#!/bin/bash
set -e

# SSH 키 삭제
rm -rf /home/*/.ssh/*
rm -rf /root/.ssh/*

# 로그 정리
find /var/log -type f -exec truncate -s 0 {} \;
rm -rf /var/log/*.gz /var/log/*.1

# 히스토리 삭제
rm -f /home/*/.bash_history
rm -f /root/.bash_history

# 임시 파일 삭제
rm -rf /tmp/* /var/tmp/*

# apt 캐시 정리
apt-get clean
rm -rf /var/lib/apt/lists/*

# Machine ID 초기화 (중복 방지)
truncate -s 0 /etc/machine-id

echo "Cleanup completed for public distribution"
```

---

## 11. SBOM (Software Bill of Materials)

공개 배포 시 Box에 포함된 모든 소프트웨어 컴포넌트를 문서화합니다.

### SBOM 생성 도구

| 도구 | 형식 | 설명 |
|------|------|------|
| syft | SPDX, CycloneDX | Anchore 제공, 컨테이너/파일시스템 분석 |
| trivy | SPDX, CycloneDX | 보안 스캐너 겸용, SBOM 생성 지원 |
| dpkg-licenses | 텍스트 | Debian 패키지 라이선스 추출 |

### syft로 SBOM 생성

```bash
#!/bin/bash
# scripts/generate-sbom.sh

# syft 설치
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin

# SPDX 형식으로 SBOM 생성
syft dir:/ -o spdx-json > /etc/vagrant-box/sbom-spdx.json

# CycloneDX 형식으로 SBOM 생성
syft dir:/ -o cyclonedx-json > /etc/vagrant-box/sbom-cyclonedx.json

# 사람이 읽기 쉬운 형식
syft dir:/ -o table > /etc/vagrant-box/sbom-table.txt

echo "SBOM generated: /etc/vagrant-box/sbom-*.json"
```

### trivy로 SBOM + 취약점 스캔

```bash
#!/bin/bash
# scripts/sbom-scan.sh

# trivy 설치
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

# SBOM 생성
trivy rootfs / --format spdx-json -o /etc/vagrant-box/sbom-trivy.json

# 취약점 스캔 (SBOM 기반)
trivy sbom /etc/vagrant-box/sbom-trivy.json --severity HIGH,CRITICAL

# 취약점 보고서 생성
trivy rootfs / --format json -o /etc/vagrant-box/vuln-report.json
```

### 수동 SBOM 템플릿 (SPDX)

```json
{
  "spdxVersion": "SPDX-2.3",
  "dataLicense": "CC0-1.0",
  "SPDXID": "SPDXRef-DOCUMENT",
  "name": "dasomel-ubuntu-24.04-vagrant-box",
  "documentNamespace": "https://github.com/dasomel/ubuntu-24.04/sbom",
  "creationInfo": {
    "created": "2024-01-01T00:00:00Z",
    "creators": ["Tool: syft-1.0.0", "Organization: dasomel"]
  },
  "packages": [
    {
      "name": "ubuntu",
      "versionInfo": "24.04",
      "SPDXID": "SPDXRef-Package-ubuntu",
      "downloadLocation": "https://cloud-images.ubuntu.com/",
      "licenseConcluded": "Various",
      "licenseDeclared": "Various"
    }
  ]
}
```

### Packer 빌드에 SBOM 통합

```hcl
# packer/vmware-amd64.pkr.hcl

build {
  sources = ["source.vmware-iso.ubuntu-vmware-amd64"]

  # 기존 프로비저닝...
  provisioner "shell" {
    scripts = [
      "scripts/01-base.sh",
      # ...
      "scripts/99-cleanup.sh"
    ]
  }

  # SBOM 생성 (cleanup 후)
  provisioner "shell" {
    script = "scripts/generate-sbom.sh"
  }

  post-processor "vagrant" {
    output = "ubuntu-24.04-vmware-amd64.box"
  }
}
```

### SBOM 배포 위치

| 위치 | 형식 | 용도 |
|------|------|------|
| Box 내부 (`/etc/vagrant-box/sbom-*.json`) | SPDX/CycloneDX | Box 사용자 확인용 |
| GitHub Release | JSON | 다운로드 전 확인용 |
| GitHub Repository | JSON | 버전 관리 |
| Vagrant Cloud 설명 | 링크 | 사용자 안내 |

### SBOM 체크리스트

- [ ] syft 또는 trivy로 SBOM 생성
- [ ] SPDX 또는 CycloneDX 형식 선택
- [ ] Box 내부 `/etc/vagrant-box/` 에 포함
- [ ] GitHub Release에 첨부
- [ ] README에 SBOM 위치 안내
- [ ] 취약점 스캔 결과 확인

---

## 12. 최종 체크리스트

배포 전 확인사항:

- [ ] LICENSE 파일 루트에 추가
- [ ] NOTICE 파일에 서드파티 고지 작성
- [ ] README.md에 라이선스 배지 추가
- [ ] Box 내부에 /etc/vagrant-box/LICENSE 포함
- [ ] Vagrant Cloud 설명에 라이선스 명시
- [ ] GitHub 저장소 라이선스 설정
- [ ] 라이선스 호환성 검토 완료
- [ ] 상표권 침해 여부 확인
- [ ] 민감 정보 제거 확인
- [ ] cleanup.sh 실행 완료
- [ ] SBOM 생성 및 포함

---

## 13. 서드파티 라이선스 확인

```bash
# Box 내 설치된 패키지 라이선스 확인
dpkg-query -W -f='${Package}\t${License}\n'

# 특정 패키지 라이선스 상세
apt-cache show <package> | grep -i license

# 라이선스 파일 위치
ls /usr/share/doc/*/copyright
```

---

## 참고 자료

- [Choose a License](https://choosealicense.com/)
- [SPDX License List](https://spdx.org/licenses/)
- [CISA SBOM 가이드라인](https://www.cisa.gov/sbom)
- [Ubuntu 상표 정책](https://ubuntu.com/legal/trademarks)
- [CNCF 상표 가이드라인](https://www.cncf.io/brand-guidelines/)
