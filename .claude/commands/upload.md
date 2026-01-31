# /upload - Vagrant Cloud 업로드

빌드된 Box를 Vagrant Cloud에 업로드합니다.

## 사전 확인

```bash
echo "=== Upload Preparation ===" && \
echo "Built boxes:" && ls -lh packer/*.box 2>/dev/null || echo "No boxes found" && \
echo "" && echo "Current version in upload script:" && grep -E "^VERSION=" upload-boxes.sh 2>/dev/null || echo "VERSION not found" && \
echo "" && echo "Vagrant Cloud auth:" && vagrant cloud auth whoami 2>/dev/null || echo "Not logged in"
```

## 업로드 전 체크리스트

- [ ] Box 파일 존재 확인
- [ ] 버전 번호 확인 (중복 방지)
- [ ] Vagrant Cloud 인증 상태
- [ ] CHANGELOG.md 업데이트 여부

## 실행

```bash
./upload-boxes.sh
```

## 업로드 후 확인

```bash
vagrant cloud box show <username>/kube-ready-box
```

## 주의사항

- 버전 번호 중복 시 업로드 실패
- 대용량 파일로 업로드 시간 소요 (병렬 업로드 권장)
- 업로드 중단 시 재시도 가능
