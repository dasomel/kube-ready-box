# DESIGN-ko.md

[English](DESIGN.md) | 한국어

## 제품 아키타입 (Product archetype)

`archetype: Developer Tool`

kube-ready-box는 Kubernetes 테스트베드 및 베어메탈 환경을 위한 인프라 이미지 패키징 자동화 스위트입니다.

## 제품 성격 (Personality)

- **밀도 (Density):** 높음 (High — CLI 및 빌드 매트릭스 로그 출력)
- **시각적 비중:** 터미널 네이티브 로그 레벨 및 Vagrant 박스 자산 테이블
- **강조 색상:** 앰버 (`#f59e0b`)

## 시맨틱 토큰 매핑 (Token mapping)

```yaml
tokens:
  bgCanvas: var(--of-color-bg-canvas, #0a0a0a)
  bgSurface: var(--of-color-bg-surface, #171717)
  bgSurfaceRaised: var(--of-color-bg-surface-raised, #262626)
  textPrimary: var(--of-color-text-primary, #ededed)
  textSecondary: var(--of-color-text-secondary, #a1a1a1)
  textMuted: var(--of-color-text-muted, #737373)
  borderDefault: var(--of-color-border-default, #262626)
  accentPrimary: var(--of-color-accent-primary, #f59e0b)
  danger: var(--of-color-status-danger, #ef4444)
  success: var(--of-color-status-success, #22c55e)
```
