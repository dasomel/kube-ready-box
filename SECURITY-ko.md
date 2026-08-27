# 보안 정책 (Security Policy)

[English](SECURITY.md) | 한국어

## 지원 대상 버전

| 버전 | 지원 여부 |
| ---- | -------- |
| v0.x | :white_check_mark: |

## 보안 범위 및 VM 이미지

`kube-ready-box`는 Kubernetes 베어메탈 및 가상화 노드 프로토타이핑을 위한 Vagrant/Cloud 기반 이미지를 빌드합니다.

- 이미지 빌드 시 개인 키, 하드코딩된 패스워드, 프로덕션 시크릿이 베이스 이미지에 포함되지 않아야 합니다.
- 시스템 서비스, 커널 파라미터, 컨테이너 런타임(containerd/CRI-O)은 CIS Kubernetes 벤치마크 표준을 준수합니다.

## 취약점 보고 절차 (Reporting a Vulnerability)

보안 취약점은 공개 이슈로 등록하지 마시고, GitHub Private Vulnerability Reporting을 통해 비공개로 보고해 주십시오.

참조: [OpenForge Security Standard](https://github.com/dasomel/openforge/blob/main/docs/security.md)
