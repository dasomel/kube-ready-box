# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- GitHub Actions workflow for automated AMD64 builds
- ARM64 build improvements for VirtualBox
- Additional CNI plugin examples
- Performance benchmarking results

## [0.1.0] - 2025-01-25

### Added
- Initial release of dasomel/ubuntu-24.04 Vagrant Box
- Ubuntu 24.04 LTS base with cloud-init
- Multi-architecture support: AMD64 and ARM64
- Multi-provider support: VirtualBox 7.1+ and VMware Fusion
- Comprehensive OS-level optimizations for Kubernetes workloads:
  - Kernel parameter tuning (sysctl)
  - Resource limits configuration (ulimit, systemd)
  - Network performance optimization (TCP buffers, conntrack, NIC tuning)
  - Disk I/O optimization (scheduler, read-ahead, mount options)
  - Ubuntu 24.04 specific tuning (THP, systemd-oomd)
- Kubernetes prerequisites pre-configured:
  - Swap disabled
  - Required kernel modules (br_netfilter, overlay, etc.)
  - IP forwarding enabled
  - Bridge netfilter enabled
- Automated provisioning scripts:
  - 01-base.sh - Base system updates
  - 02-os-tuning.sh - Kernel and resource tuning
  - 03-os-packages.sh - Essential packages
  - 04-k8s-prereq.sh - Kubernetes prerequisites
  - 05-disk-tuning.sh - Disk I/O optimization
  - 06-nic-tuning.sh - Network interface tuning
  - ubuntu2404-tuning.sh - Ubuntu 24.04 specific settings
  - 07-check-tuning.sh - Verification script
  - license-info.sh - License information
  - generate-sbom.sh - SBOM generation
  - 99-cleanup.sh - Pre-packaging cleanup
- Documentation:
  - Comprehensive README with quick start guide
  - Korean README (README.ko.md)
  - Detailed usage guide (usage.md)
  - Kubernetes post-install guide (k8s-post-install.md)
  - Legal and licensing guide (legal.md)
  - Packer build guide (packer/README.md)
- License and compliance:
  - MIT License
  - NOTICE file with third-party attributions
  - In-box license information at /etc/vagrant-box/
  - SBOM (Software Bill of Materials) using trivy
- Build automation:
  - build.sh script with platform detection
  - Parallel build support for multiple boxes
  - Comprehensive error handling and logging
- Testing infrastructure:
  - Test Vagrantfiles for VirtualBox and VMware
  - Box verification scripts

### Technical Details

**Supported Platforms:**
- VirtualBox 7.1+ (AMD64, ARM64)
- VMware Fusion (AMD64, ARM64)

**Base Image:**
- Ubuntu 24.04.3 LTS (Noble Numbat)
- AMD64: ubuntu-24.04.3-live-server-amd64.iso
- ARM64: ubuntu-24.04.3-live-server-arm64.iso

**Box Specifications:**
- Default CPU: 2 cores
- Default Memory: 2048 MB
- Default Disk: 20 GB
- SSH User: vagrant/vagrant
- Network: NAT (default)

**Optimizations Applied:**
- Kernel: vm.swappiness=0, net.ipv4.ip_forward=1, fs.inotify.max_user_watches=524288
- Limits: nofile=1048576, nproc=unlimited, memlock=unlimited
- Network: TCP window sizes, conntrack table size, NIC ring buffers
- Disk: noop/none scheduler, read-ahead 512, noatime mount option
- Ubuntu 24.04: THP madvise, systemd-oomd tweaks

**NOT Included (User Installation Required):**
- Container runtime (containerd, CRI-O)
- Kubernetes components (kubeadm, kubelet, kubectl)
- CNI plugins (Cilium, Flannel, Calico)

### Known Issues

**VirtualBox ARM64 on Apple Silicon:**
- Issue: boot_command scancode failures during automated installation
- Workaround: Manual installation or use VMware provider
- Status: Tracked in VirtualBox upstream

**VMware ARM64 Compatibility:**
- Requires VMware Fusion on Apple Silicon
- VNC port must be available (5900-5999)

### Security

- No hardcoded secrets or credentials (except default vagrant user)
- SSH keys properly cleaned during build
- All logs and history cleared before packaging
- Machine ID reset for uniqueness

### Build Information

- Packer Version: 1.8+
- Built with: Packer + Shell provisioners
- Compression: Level 9 (gzip)
- Average Build Time: 15-25 minutes per box
- Average Box Size: 2.0-2.5 GB compressed

### Credits

- Built with [Packer](https://www.packer.io/) by HashiCorp
- Based on [Ubuntu](https://ubuntu.com/) by Canonical
- Optimizations inspired by Kubernetes documentation
- SBOM generated with [Trivy](https://trivy.dev/)

## [0.9.0] - 2025-01-20 (Beta)

### Added
- Beta release for internal testing
- Basic Ubuntu 24.04 setup
- Initial Kubernetes prerequisites

### Changed
- Migrated from Ubuntu 22.04 to 24.04

### Removed
- Legacy Ubuntu 22.04 support

---

## Release Notes Format

Each release follows this structure:

### Added
- New features and functionality

### Changed
- Changes to existing functionality

### Deprecated
- Features that will be removed in future releases

### Removed
- Features removed in this release

### Fixed
- Bug fixes

### Security
- Security updates and patches

---

## How to Use

To see what's new in a specific version:

```bash
# Check box version
vagrant ssh -c "cat /etc/vagrant-box/info.txt"

# View changelog
curl -s https://raw.githubusercontent.com/dasomel/kube-ready-box/main/CHANGELOG.md
```

## Upgrade Guide

### From Beta (0.9.0) to 0.1.0

1. Remove old box:
```bash
vagrant box remove dasomel/ubuntu-24.04 --box-version 0.9.0
```

2. Update Vagrantfile (no changes required for 0.1.0)

3. Pull new version:
```bash
vagrant box add dasomel/ubuntu-24.04 --version 0.1.0
```

4. Recreate VMs:
```bash
vagrant destroy -f
vagrant up
```

---

[Unreleased]: https://github.com/dasomel/kube-ready-box/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/dasomel/kube-ready-box/releases/tag/v0.1.0
