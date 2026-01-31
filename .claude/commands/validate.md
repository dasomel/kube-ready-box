# /validate - 전체 검증

Packer 템플릿, 스크립트, 설정을 종합적으로 검증합니다.

## 자동 검증 실행

```bash
echo "=== Validation Start ===" && cd packer && \
echo "1. Packer Init..." && packer init . && \
echo "" && echo "2. Packer Validate..." && packer validate . && \
echo "" && echo "3. Script Permissions..." && \
find scripts -name "*.sh" ! -perm -u+x -print | while read f; do echo "WARN: $f missing execute permission"; done && \
echo "" && echo "4. Required Files..." && \
for f in http/autoinstall/user-data http/autoinstall/meta-data templates/Vagrantfile.template; do \
  [ -f "$f" ] && echo "OK: $f" || echo "MISSING: $f"; \
done && \
echo "" && echo "=== Validation Complete ==="
```

## 검증 항목

### Packer 템플릿
- 문법 오류
- 변수 참조 확인
- 빌더 설정 유효성

### 스크립트
- 실행 권한 (chmod +x)
- Bash 문법 (shellcheck 권장)
- 필수 스크립트 존재

### Cloud-init
- user-data YAML 문법
- 필수 패키지 목록
- SSH 키 설정

## 권장 사항

문제 발견 시 `/add-mistake`로 패턴을 기록하여 재발 방지
