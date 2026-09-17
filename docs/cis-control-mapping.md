# CIS Kubernetes Benchmark Control-ID Mapping (#5)

`docs/public-rfp-readiness.md`가 "CIS/Kubernetes hardening의 적용 가능 항목 목록화"를
미기재 상태로 남긴 이유는 정확한 control 번호를 기억에 의존해 지어내지 않기 위해서였다.
이 문서는 그 후속 작업으로, control ID와 원문을 **kube-bench의 공개 체크 정의 파일에서
그대로** 가져와 이 저장소의 실제 상태와 대조한다.

## 소스

- 저장소: [`aquasecurity/kube-bench`](https://github.com/aquasecurity/kube-bench)
- 릴리스: `v0.16.0` (main 브랜치 HEAD `9f133cb7509ce1dbedfc860e94474588000e25ac` 기준 조회)
- 적용 벤치마크 버전: `cfg/cis-1.24`(kube-bench가 제공하는 가장 최신 `cis-1.x` 디렉터리 —
  `cfg/` 목록에 `cis-1.5`~`cis-1.24`가 있으며 `cis-1.24`가 최댓값)
  - `cfg/cis-1.24/node.yaml` — 최종 변경 커밋 `fa478ce238fd1f8063d1cce42077fa4bf32102c7`
    (2024-10-16)
  - `cfg/cis-1.24/policies.yaml` — 최종 변경 커밋 `c40b2a72e2be30a4ef4b3c77a98467e2f9f3e5fd`
    (2025-03-04)
- 조회 일자: 2026-09-07 (`gh api repos/aquasecurity/kube-bench/contents/...`)

kube-bench 자체 문서(`README.md`)가 명시하듯 "K8s 릴리스와 CIS 벤치마크 릴리스는 1:1이
아니다" — 어떤 kube-bench 버전이 어떤 K8s 버전을 커버하는지는 `docs/platforms.md`를
참고하라고 되어 있으며, 이 저장소는 커버리지 표를 재인용하지 않는다(원문 미확인 항목을
지어내지 않기 위함).

## 범위와 전제

이 저장소(`kube-ready-box`)는 **kubelet/kubeadm/kube-proxy를 설치하지 않는** OS 이미지다
(`packer/scripts/04-k8s-prereq.sh` 마지막 안내: "다음 단계에서 사용자가 직접 설치:
kubeadm, kubelet, kubectl"). 따라서 kube-bench의 "4 Worker Node" 그룹 대부분은 이미지
시점에 감사할 파일/프로세스 자체가 존재하지 않는다. `5.2`(Pod Security Standards)와
`5.3`/`5.4`/`5.5`는 클러스터 API 서버/어드미션 컨트롤러가 있어야 성립하는 컨트롤이라
OS 이미지 레이어와 무관하다 — 표에는 이미지와 접점이 있는 `5.7.2`(seccomp)만 포함했다.

**image-enforced로 표시된 항목은 없다.** 이미지가 이 컨트롤을 강제하는 코드 줄을 가리킬
수 없는 한 image-enforced로 표시하지 말라는 지침에 따라, 이 저장소가 실제로 관련 설정을
준비해두는 2개 컨트롤만 `image-prepared`로, 나머지는 `not-applicable-at-image-layer`로
표시했다.

## 4.1 Worker Node Configuration Files

kubelet 서비스 파일/kubeconfig/CA 파일은 이미지 빌드 시점에 존재하지 않는다
(`kubeadm join` 이후 생성됨). 10개 컨트롤 전부 이미지 레이어에서 감사 불가능.

| Control ID | 원문 (verbatim) | 이 이미지의 현재 상태 | Status |
|---|---|---|---|
| 4.1.1 | Ensure that the kubelet service file permissions are set to 600 or more restrictive (Automated) | 파일 자체가 이미지에 없음(`kubeadm join` 후 생성) | not-applicable-at-image-layer |
| 4.1.2 | Ensure that the kubelet service file ownership is set to root:root (Automated) | 상동 | not-applicable-at-image-layer |
| 4.1.3 | If proxy kubeconfig file exists ensure permissions are set to 600 or more restrictive (Manual) | 상동 | not-applicable-at-image-layer |
| 4.1.4 | If proxy kubeconfig file exists ensure ownership is set to root:root (Manual) | 상동 | not-applicable-at-image-layer |
| 4.1.5 | Ensure that the --kubeconfig kubelet.conf file permissions are set to 600 or more restrictive (Automated) | 상동 | not-applicable-at-image-layer |
| 4.1.6 | Ensure that the --kubeconfig kubelet.conf file ownership is set to root:root (Automated) | 상동 | not-applicable-at-image-layer |
| 4.1.7 | Ensure that the certificate authorities file permissions are set to 600 or more restrictive (Manual) | 상동 | not-applicable-at-image-layer |
| 4.1.8 | Ensure that the client certificate authorities file ownership is set to root:root (Manual) | 상동 | not-applicable-at-image-layer |
| 4.1.9 | If the kubelet config.yaml configuration file is being used validate permissions set to 600 or more restrictive (Manual) | 상동 | not-applicable-at-image-layer |
| 4.1.10 | If the kubelet config.yaml configuration file is being used validate file ownership is set to root:root (Manual) | 상동 | not-applicable-at-image-layer |

## 4.2 Kubelet

kubelet 자체가 설치되지 않으므로 대부분 컨트롤은 kubeadm이 join 시점에 기본값으로
결정한다. 이미지가 실제로 관련 사전조건을 준비해두는 것은 `4.2.6` 하나뿐이다.

| Control ID | 원문 (verbatim) | 이 이미지의 현재 상태 | Status |
|---|---|---|---|
| 4.2.1 | Ensure that the --anonymous-auth argument is set to false (Automated) | kubelet 미설치, 이미지가 관여하는 설정 없음 (kubeadm 기본값에 위임) | not-applicable-at-image-layer |
| 4.2.2 | Ensure that the --authorization-mode argument is not set to AlwaysAllow (Automated) | 상동 | not-applicable-at-image-layer |
| 4.2.3 | Ensure that the --client-ca-file argument is set as appropriate (Automated) | 상동 | not-applicable-at-image-layer |
| 4.2.4 | Verify that the --read-only-port argument is set to 0 (Manual) | 상동 | not-applicable-at-image-layer |
| 4.2.5 | Ensure that the --streaming-connection-idle-timeout argument is not set to 0 (Manual) | 상동 | not-applicable-at-image-layer |
| 4.2.6 | Ensure that the --protect-kernel-defaults argument is set to true (Automated) | `packer/scripts/02-os-tuning.sh`가 `vm.overcommit_memory = 1`, `vm.panic_on_oom = 0`를 명시적으로 설정 — kubelet이 `--protect-kernel-defaults=true`로 부팅할 때 검증하는 커널 sysctl 중 2개와 일치. 단, protect-kernel-defaults가 실제로 검증하는 전체 sysctl 집합(`kernel.panic`, `kernel.panic_on_oops`, `kernel.keys.root_maxbytes` 등)은 이미지가 설정하지 않으므로 join 후 kubelet이 실제로 이 플래그로 정상 기동하는지는 별도 확인 필요 | image-prepared (needs post-join verification) |
| 4.2.7 | Ensure that the --make-iptables-util-chains argument is set to true (Automated) | 이미지가 iptables 유틸 체인과 무관한 K8s 사전조건 패키지(socat/conntrack/ipset/ipvsadm/ebtables, `04-k8s-prereq.sh`)만 설치 — 이 플래그 자체와 직접 연결되는 설정 없음 | not-applicable-at-image-layer |
| 4.2.8 | Ensure that the --hostname-override argument is not set (Manual) | 이미지가 관여하는 설정 없음 | not-applicable-at-image-layer |
| 4.2.9 | Ensure that the eventRecordQPS argument is set to a level which ensures appropriate event capture (Manual) | 상동 | not-applicable-at-image-layer |
| 4.2.10 | Ensure that the --tls-cert-file and --tls-private-key-file arguments are set as appropriate (Manual) | 상동 (kubeadm이 join 시 인증서 발급) | not-applicable-at-image-layer |
| 4.2.11 | Ensure that the --rotate-certificates argument is not set to false (Automated) | 상동 | not-applicable-at-image-layer |
| 4.2.12 | Verify that the RotateKubeletServerCertificate argument is set to true (Manual) | 상동 | not-applicable-at-image-layer |
| 4.2.13 | Ensure that the Kubelet only makes use of Strong Cryptographic Ciphers (Manual) | 상동 | not-applicable-at-image-layer |

## 5.2 Pod Security Standards / 5.7 General Policies (이미지와 접점이 있는 항목만)

`5.2.x` 13개 전부는 클러스터 어드미션 컨트롤(Pod Security Admission 등) 레이어이며 OS
이미지 빌드와 무관하다 — 개별 나열 대신 이 절에서 한 번에 not-applicable로 처리한다.
`5.7.2`만 이미지가 커널 레벨 전제조건을 검증해주므로 별도 표기.

| Control ID | 원문 (verbatim) | 이 이미지의 현재 상태 | Status |
|---|---|---|---|
| 5.2.1 ~ 5.2.13 | Pod Security Standards (13개 전체, 클러스터 어드미션 컨트롤러 필요) | 이미지 빌드 시점에는 API 서버/어드미션 컨트롤러가 존재하지 않음 | not-applicable-at-image-layer |
| 5.7.2 | Ensure that the seccomp profile is set to docker/default in your Pod definitions (Manual) | Pod spec 설정 자체는 이미지 범위 밖이지만, seccomp 커널 인터페이스 가용성은 `security/workload-security-check.sh`의 `seccomp`(`/proc/self/status`의 `Seccomp:` 라인 확인)와 `seccomp_capability`(`/proc/sys/kernel/seccomp/actions_avail`) 체크, 그리고 `tools/node-readiness-attest.sh`의 `seccomp` 체크가 부팅 시점에 확인 | image-prepared (needs post-join verification) |

## 요약

| Status | 개수 |
|---|---|
| image-enforced | 0 |
| image-prepared (needs post-join verification) | 2 (4.2.6, 5.7.2) |
| not-applicable-at-image-layer | 35 |
| gap | 0 |

`gap`(이미지가 준비할 수 있는데 안 하고 있는 항목)으로 분류된 컨트롤은 없다 — worker
node 컨트롤 대부분이 kubelet 설치 이후에만 의미를 갖는 구조이기 때문이다. 이는 "이
이미지가 CIS를 잘 지킨다"는 뜻이 아니라 "이 레이어에서 검증 가능한 항목이 원래
적다"는 뜻이며, 실제 준수 여부는 아래 post-join 검증으로만 확인 가능하다.

## Join 이후 검증 방법 (kube-bench README 기준)

kube-bench README가 문서화하는 표준 실행 방법은 클러스터에 Job으로 배포하는 것이다:

```bash
kubectl apply -f job.yaml   # kube-bench 저장소가 제공하는 job.yaml
kubectl get pods            # kube-bench-xxxxx 파드가 Completed 될 때까지 대기
kubectl logs kube-bench-xxxxx   # 결과는 파드 로그에 기록됨
```

README는 "기본적으로 kube-bench는 머신에서 실행 중인 Kubernetes 버전을 감지해 실행할
테스트 세트를 결정한다"고 명시하고, 더 자세한 실행 방법은 kube-bench 저장소의
`docs/running.md`를 보라고 안내한다 (이 문서의 세부 내용은 인용하지 않음 — 미확인
원문을 옮기지 않기 위함). `job.yaml`은 호스트 PID 네임스페이스와 호스트 설정
디렉터리 접근이 필요하다고 README에 명시되어 있다.

이 저장소의 어떤 스크립트도 kube-bench를 실행하지 않는다 — 위는 외부 검증 절차 안내일
뿐, join 이후 실제 실행 증거는 이 저장소 범위 밖이다.
