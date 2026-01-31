# /build - Packer Box 빌드

Box 이미지를 빌드합니다. 인라인 bash로 현재 상태를 사전 확인합니다.

## 사전 정보 수집

```bash
cd packer && echo "=== Build Environment ===" && \
echo "Available targets:" && ls -1 *.pkr.hcl | sed 's/.pkr.hcl//' && \
echo "" && echo "Existing boxes:" && ls -la *.box 2>/dev/null || echo "None" && \
echo "" && echo "Last modified templates:" && ls -lt *.pkr.hcl | head -3
```

## 빌드 옵션

| Target | Command | Description |
|--------|---------|-------------|
| VMware ARM64 | `./build.sh vmware-arm64` | Apple Silicon용 |
| VMware AMD64 | `./build.sh vmware-amd64` | Intel Mac/Linux용 |
| VirtualBox ARM64 | `./build.sh virtualbox-arm64` | VirtualBox 7.1+ |
| VirtualBox AMD64 | `./build.sh virtualbox-amd64` | 표준 VirtualBox |
| All | `./build.sh all` | 4개 병렬 빌드 |

## 실행

사용자에게 타겟을 확인한 후 빌드를 실행합니다:

```bash
cd packer && ./build.sh <target>
```

## 빌드 후 검증

빌드 완료 후 자동으로 검증합니다:
- Box 파일 크기 확인
- Vagrant box list로 등록 확인
- 선택적으로 test-vm에서 부팅 테스트
