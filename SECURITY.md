# Security Policy

English | [한국어](SECURITY-ko.md)

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| v0.x    | :white_check_mark: |

## Security Scope & VM Images

`kube-ready-box` builds pre-configured Vagrant and cloud base images for Kubernetes bare-metal / VM node prototyping.

- Image builds must never bake private keys, hardcoded passwords, or production secrets into base box images.
- Systemd units, kernel sysctls, and container runtimes (containerd/CRI-O) must conform to CIS Kubernetes Benchmark standards.

## Reporting a Vulnerability

Please do not open public issues for security vulnerabilities. Use GitHub Private Vulnerability Reporting or contact the maintainers directly.

Reference: [OpenForge Security Standard](https://github.com/dasomel/openforge/blob/main/docs/security.md)
