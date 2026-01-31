# /test-box - Box 부팅 테스트

빌드된 Box를 실제로 부팅하여 검증합니다.

## 사전 확인

```bash
echo "=== Test Environment ===" && \
echo "Available boxes:" && ls -lh packer/*.box 2>/dev/null && \
echo "" && echo "test-vm status:" && \
[ -f test-vm/Vagrantfile ] && echo "Vagrantfile exists" || echo "Vagrantfile not found" && \
cd test-vm 2>/dev/null && vagrant status 2>/dev/null || echo "No existing VM"
```

## 테스트 절차

### 1. Box 등록
```bash
vagrant box add --name test-kube-ready packer/<box-file>.box --force
```

### 2. VM 시작
```bash
cd test-vm && vagrant up
```

### 3. 검증 항목
```bash
vagrant ssh -c "
echo '=== System Info ===' && uname -a && \
echo '' && echo '=== K8s Prerequisites ===' && \
echo 'Swap:' && swapon --show && \
echo 'Modules:' && lsmod | grep -E 'overlay|br_netfilter' && \
echo 'Sysctl:' && sysctl net.bridge.bridge-nf-call-iptables net.ipv4.ip_forward
"
```

### 4. 정리
```bash
cd test-vm && vagrant destroy -f
vagrant box remove test-kube-ready
```

## 검증 체크리스트

- [ ] VM 정상 부팅
- [ ] SSH 접속 가능
- [ ] Swap 비활성화
- [ ] 커널 모듈 로드됨
- [ ] Sysctl 설정 적용됨
- [ ] 네트워크 연결 정상
