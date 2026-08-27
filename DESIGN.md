# DESIGN.md

English | [한국어](DESIGN-ko.md)

## Product archetype

`archetype: Developer Tool`

kube-ready-box is an infrastructure image packaging automation suite for Kubernetes testbeds and bare-metal environments.

## Product personality

- **Density:** High (compact CLI and build matrix log outputs)
- **Visual weight:** Terminal-native log levels and Vagrant box asset tables
- **Accent:** Amber (`#f59e0b`) for box release tags and build metadata

## Token mapping

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
