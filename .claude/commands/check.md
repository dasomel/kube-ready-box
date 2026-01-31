# /check - Quick Validation

Packer 템플릿과 스크립트를 빠르게 검증합니다.

## 실행 내용

1. Packer 템플릿 문법 검증
2. 스크립트 실행 권한 확인
3. 필수 파일 존재 확인

## 명령어

```bash
cd packer && ./build.sh validate
```

## 검증 항목

- [ ] `packer validate .` 성공
- [ ] 모든 scripts/*.sh 에 실행 권한
- [ ] http/autoinstall/user-data 존재
- [ ] templates/ 폴더 템플릿 존재
