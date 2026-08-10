# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [NixOS-0.1.0] - 2026-08-10

### Added
- **NixOS Kube-Ready Vagrant Box 0.1.0**: 선언적 불변 Linux OS 기반 Kubernetes 노드 이미지 구축
- **In-Guest License & Metadata**: `/etc/vagrant-box/info.txt`, `/etc/vagrant-box/LICENSE` (MIT License) 및 `/etc/vagrant-box/manifest.json` 내장
- **Software Bill of Materials (SBOM)**: Nix Store 매니페스트 및 SPDX 규격 메타데이터 탑재
- **Vagrant Cloud Publish Automation**: `nixos/upload-nixos.sh` 스크립트를 통한 `dasomel/nixos-kube-ready` 0.1.0 배포 자동화
- **CI/CD Integration**: `.github/workflows/build-nixos.yml` 기반 GitHub Actions 아티팩트 자동 빌드 지원

## [1.1.0] - 2026-07-18

### Added
- Ubuntu 26.04 LTS (Resolute Raccoon, kernel Linux 7.0) coexist support
  - Version-parameterized Packer templates (`var.ubuntu_version`, default 24.04)
  - `build.sh --version=26.04` and `UBUNTU_VERSION=26.04 ./upload-boxes.sh`
  - GitHub Actions `workflow_dispatch` `ubuntu_version` input
  - Runtime-detected SBOM and license metadata (no hardcoded version)

### Changed
- ubuntu-tuning.sh: 버전 자동 감지(/etc/os-release) + 분기 구조 추가, EEVDF(커널 6.6+)에서 sysctl→debugfs 이동된 무효 CFS 스케줄러 튜너블(kernel.sched_min/wakeup_granularity_ns) 제거
- 02-os-tuning.sh: vm.max_map_count=1048576 추가 (K8s 권장, Ubuntu 26.04 systemd 기본값과 정렬 — 낮은 값으로 기본 다운그레이드 방지)
- `packer/scripts/ubuntu2404-tuning.sh` renamed to `ubuntu-tuning.sh`
- `packer/scripts/generate-sbom.sh`: version derived from `/etc/os-release` at runtime
- `packer/scripts/license-info.sh`: all version strings derived from `/etc/os-release`
- `packer/scripts/upload-all.sh`: marked legacy, minimally parameterized via `UBUNTU_VERSION`
- `packer/scripts/01-base.sh`: unattended-upgrades 제거를 `apt-get remove` → `apt-get purge`로 변경 (logind InhibitDelayMaxSec=30 drop-in까지 완전 제거)
- `packer/scripts/01-base.sh`: needrestart 제거 추가 (Qualys 로컬 권한 상승 CVE 5건: CVE-2024-48990~48992, CVE-2024-10224, CVE-2024-11003)
- `packer/scripts/03-os-packages.sh`: K8s 에코시스템 도구에 `apparmor-utils` 추가 (K8s 공식 보안 체크리스트)
- `packer/scripts/04-k8s-prereq.sh`: CSI 스토리지 전제조건 추가 (Longhorn V1 엔진 요구사항 — `open-iscsi`, `cryptsetup`, `dmsetup`, `iscsi_tcp` 모듈 자동 로드 + `iscsid` 활성화)
- `packer/scripts/04-k8s-prereq.sh`: bpffs(`/sys/fs/bpf`) 영구 마운트 추가 (Cilium eBPF 리소스 유지용)
- `packer/scripts/01-base.sh`: systemd-timesyncd → chrony 전환 (Ubuntu 25.10+/26.04 기본 데몬 정렬, K8s/etcd 권장), 한국 NTP 서버(time.bora.net 등)를 `/etc/chrony/sources.d/kr-ntp.sources`로 이관
- `packer/scripts/03-os-packages.sh`: auditd 설치 추가 (CIS 벤치마크 대응, 기본 비활성화 — EKS/GKE/AKS 노드 이미지 관행, I/O 오버헤드 방지 설정 포함)
- `docs/k8s-post-install.md`: "노드 운영 주의사항" 섹션 추가 (unattended-upgrades/ufw/crictl/Longhorn 안내), multipath-tools/OpenEBS/chrony/auditd 안내 확장

### Fixed
- CI: pin Packer to 1.15.4 (validate.yml was 1.10.0; build workflows `PACKER_VERSION` 1.10.0 → 1.15.4)
- VMware templates: add required `network_adapter_type = "vmxnet3"` (newer packer-plugin-vmware requires it; was failing `packer validate` in CI)
- CI shellcheck: run with `--severity=warning` and add `.shellcheckrc` (disable SC1091 for runtime `/etc/os-release` sourcing)
- `plugins.pkr.hcl`: add `ubuntu_version` validation (24.04/26.04), bump `required_version` to `>= 1.10.0`
- `upload-boxes.sh`: validate `UBUNTU_VERSION` (24.04/26.04)
- Documentation (README, CLAUDE.md) updated for dual-version support

### Planned
- Additional CNI plugin examples
- Performance benchmarking results

## [0.2.3] - 2026-05-01

### Security
- Address CVE-2026-23268, CVE-2026-23269, CVE-2026-23403~23411 (Linux kernel/AppArmor:
  unprivileged AppArmor profile load/replace/remove leading to DoS, kernel memory disclosure,
  local privilege escalation, container escape)
- Address CVE-2026-23144, CVE-2026-23171, CVE-2026-23204, CVE-2025-71238
  (DAMON sysfs DoS/leak, bonding UAF, qla2xxx double-free)
- Address CVE-2025-32462, CVE-2025-32463 (sudo chroot local privilege escalation,
  KEV-listed 2025-09-29)
- Address CVE-2025-26465, CVE-2025-26466 (OpenSSH VerifyHostKeyDNS server impersonation,
  ping-handling resource exhaustion DoS)

### Changed
- `packer/scripts/01-base.sh`: switch from `apt-get upgrade` to `apt-get full-upgrade`
  so kernel security updates that pull new dependencies are actually installed
- `packer/scripts/01-base.sh`: explicit `--only-upgrade` of kernel/apparmor/sudo/openssh
  metapackages immediately after the full-upgrade pass
- `packer/plugins.pkr.hcl`: bump `box_version` default from 0.2.1 to 0.2.3
  (also fixes the long-standing 0.2.1↔0.2.2 inconsistency)

### Added
- `packer/scripts/08-security-check.sh`: build-time security audit that records
  versions of CVE-relevant packages, pending security updates, and AppArmor status
  to `/var/log/kube-ready-box-security.log`
- All four pkr.hcl templates wired to run `08-security-check.sh` after `07-check-tuning.sh`

## [0.2.2] - 2026-02-13

### Added
- `yq` (mikefarah/yq): YAML processor for Kubernetes manifest editing
  - Standalone Go binary, installed from GitHub releases
  - Auto-detects architecture (amd64/arm64)

### Changed
- Version bump from 0.2.1 to 0.2.2
- CI: Switch Vagrant Cloud auth from `VAGRANT_CLOUD_TOKEN` (short-lived JWT) to
  `HCP_CLIENT_ID`/`HCP_CLIENT_SECRET` (service principal, on-demand token generation)

### Fixed
- CI: Disable KVM kernel modules before VirtualBox build on GitHub Actions
  - `VERR_SVM_IN_USE` error resolved by unloading kvm_amd/kvm_intel modules
- CI: Vagrant Cloud publish failure due to expired HCP JWT token
  - HCP Vagrant Registry uses short-lived OAuth2 tokens (1 hour)
  - Switched to HCP service principal credentials for automatic token refresh
- Replace `dstat` with `dool` (installed from GitHub, not in Ubuntu 24.04 repos)
- Enable `universe` repository in `01-base.sh` for monitoring tools (iotop, iftop, nload, nethogs)
- AMD64 Korean mirror: GeoIP-aware fallback to default mirrors
  - `kr.archive.ubuntu.com` GeoIP redirects to `us.kr.archive.ubuntu.com` from outside Korea
  - Auto-detects `Err:` in `apt-get update` output and reverts to default mirrors
  - First `apt-get update` runs with default mirrors to ensure full universe index

### Technical Details
- Modified: `packer/scripts/01-base.sh` - Enable universe, GeoIP-aware mirror fallback
- Modified: `packer/scripts/03-os-packages.sh` - Added yq, dool from GitHub
- Modified: `.github/workflows/build-amd64.yml` - KVM disable step, HCP auth
- Modified: `.github/workflows/build-arm64.yml` - HCP auth
- CI verified: VirtualBox AMD64 ext4 (~20min) and xfs (~35min) build + publish success

## [0.2.1] - 2026-02-13

### Added
- Kubernetes ecosystem tools in `03-os-packages.sh`
  - `jq`: JSON processor for kubectl output parsing
  - `bash-completion`: Required for kubectl bash completion
  - `nfs-common`: NFS client for NFS-based PersistentVolumes
  - `sshpass`: Non-interactive SSH for cluster automation (Ansible)

### Changed
- Version bump from 0.2.0 to 0.2.1 (package enhancement)
- `build.sh` `all` command: platform-aware build (skips incompatible arch targets)
  - ARM64 platform: builds VMware ARM64 + VirtualBox ARM64, skips AMD64
  - AMD64 platform: builds VirtualBox AMD64 + VMware AMD64, skips ARM64

### Fixed
- VirtualBox ARM64 on Apple Silicon: boot_command scancode issue resolved with VirtualBox 7.2.6+
  - Previous: VirtualBox 7.2.4 and below failed to send keyboard scancodes
  - Now: VirtualBox 7.2.6 keyboard fixes enable automated builds on Apple Silicon

### Technical Details
- Modified: `packer/scripts/03-os-packages.sh` - Added "K8s ecosystem tools" section
- Modified: `packer/build.sh` - Platform-aware `all` command, re-enabled VirtualBox ARM64
- Verified: VirtualBox ARM64 build success on Apple Silicon (VirtualBox 7.2.6, 9m 39s, 2.2GB)
- No template changes required (script already referenced by all 4 pkr.hcl templates)

## [0.2.0] - 2026-02-08

### Added
- **Filesystem selection**: Choose between ext4 (default) or xfs during build
  - ext4: Mature, stable, supports online shrink, good all-around performance
  - xfs: Better for large files, parallel I/O, Kubernetes ephemeral storage quota
- New build option: `--fs` or `--filesystem` parameter
  - Example: `./build.sh vmware-arm64 --fs=xfs`
- Separate autoinstall configurations per filesystem
  - `http/autoinstall-ext4/` - ext4 (LVM layout, Ubuntu default)
  - `http/autoinstall-xfs/` - xfs (explicit storage config with EFI + LVM)
- Separate Vagrant Cloud boxes for each filesystem:
  - `dasomel/ubuntu-24.04-ext4`
  - `dasomel/ubuntu-24.04-xfs`
- Auto-detection of filesystem type in LVM auto-extend service
  - Uses `blkid` to detect ext4 vs xfs at boot time
  - Calls `resize2fs` for ext4 or `xfs_growfs` for xfs automatically
- XFS `prjquota` mount option for Kubernetes ephemeral storage quota
  - Enables `--local-storage-capacity-isolation` in kubelet
  - Applied via autoinstall late-command and disk-tuning script
- Filesystem comparison table in README

### Changed
- Box naming convention now includes filesystem type
  - New format: `ubuntu-24.04-{fs}-{provider}-{arch}.box`
  - Example: `ubuntu-24.04-xfs-vmware-arm64.box`
- AMD64 templates switched to UEFI boot mode for XFS compatibility
  - VMware AMD64: `firmware = "efi"` in vmx_data
  - VirtualBox AMD64: `--firmware efi` in vboxmanage
- Packer templates use dynamic `http_directory` based on filesystem variable
- Upload script supports multi-filesystem upload (`./upload-boxes.sh [ext4|xfs|both]`)
- GitHub Actions workflows updated with filesystem matrix (ext4/xfs)
- Validate workflow tests both ext4 and xfs for all 4 templates
- Version bump from 0.1.3 to 0.2.0 (new feature)

### Fixed
- `vmware-vmx.pkr.hcl` source_vmx default changed to `/dev/null` so `packer validate .` passes without `-only`
- XFS autoinstall uses EFI partition (fat32, flag: boot) instead of bios_grub for ARM64 compatibility
- `upload-boxes.sh` uses `tr` instead of `${var^^}` for macOS bash 3.2 compatibility
- Packer format alignment in `plugins.pkr.hcl` and `vmware-arm64.pkr.hcl`
- Shellcheck SC2002 warning in `07-check-tuning.sh` (useless cat)

### Removed
- `upgrade-amd64-box.yml` workflow (0.1.3 one-time migration, no longer needed)

### Technical Details
- Modified files:
  - `packer/plugins.pkr.hcl` - Added `filesystem` variable with validation
  - `packer/build.sh` - Added `--fs` option parsing
  - `packer/*.pkr.hcl` (4 files) - Dynamic `http_directory` and output naming
  - `packer/vmware-vmx.pkr.hcl` - Fixed source_vmx default for validation
  - `packer/scripts/05-disk-tuning.sh` - Filesystem auto-detection for resize, XFS prjquota
  - `packer/scripts/07-check-tuning.sh` - Fixed shellcheck SC2002
  - `upload-boxes.sh` - Multi-filesystem upload support
  - `.github/workflows/` - Filesystem matrix for build and validate
- New files:
  - `packer/http/autoinstall-ext4/` - ext4 autoinstall config
  - `packer/http/autoinstall-xfs/` - xfs autoinstall config (with xfsprogs)
- XFS storage config uses explicit partition layout (EFI + boot + LVM)
- All 4 templates use UEFI boot mode (EFI partition layout)
- Box sizes: ext4 ~2.2GB, xfs ~2.8GB (both thin provisioning 1TB)

## [0.1.3] - 2026-02-01

### Added
- Full disk auto-extension support at boot time
  - Automatic partition extension using growpart
  - Automatic PV (Physical Volume) extension using pvresize
  - Automatic LV and filesystem extension
  - Supports both NVMe and SATA/SCSI disks

### Changed
- Default disk size increased to 1TB (thin provisioning)
  - Actual box size remains ~2GB due to thin provisioning
  - VM disk grows dynamically as data is written
  - Eliminates need to resize disk after deployment

### Technical Details
- Modified: packer/scripts/05-disk-tuning.sh
- Added: cloud-guest-utils package for growpart
- Disk extension chain: partition → PV → LV → filesystem
- Supported disk types: /dev/sda*, /dev/nvme0n1p*

## [0.1.2] - 2026-02-01

### Added
- VirtualBox ARM64 provider support
- VMware ARM64 provider support (rebuilt with stable configuration)

### Changed
- Improved VMware Fusion build stability
  - Documented VMware Fusion restart requirement for VNC issues
  - Original 0.1.0 boot_command configuration restored for reliability

### Fixed
- VMware ARM64 build failures caused by VNC connection issues
- VirtualBox ARM64 box creation process

### Technical Details
- Providers: VMware Desktop (ARM64), VirtualBox (ARM64)
- Korean locale settings maintained from 0.1.1
- Build time: ~14 minutes per box

## [0.1.1] - 2025-01-27

### Changed
- Switch apt mirror to Korean servers for faster package downloads
  - ARM64: ports.ubuntu.com → kr.ports.ubuntu.com
  - AMD64: archive.ubuntu.com → kr.archive.ubuntu.com
  - Significantly reduces build time and package installation time
- Set default timezone to Asia/Seoul (KST, UTC+9)
- Configure Korean NTP servers for time synchronization
  - Primary: time.bora.net, time.kriss.re.kr, ntp.kornet.net
  - Fallback: ntp.ubuntu.com

### Technical Details
- Modified: packer/scripts/01-base.sh
- Auto-detection of architecture for appropriate mirror selection
- Timezone configured via timedatectl
- NTP configured via systemd-timesyncd

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

[Unreleased]: https://github.com/dasomel/kube-ready-box/compare/v0.2.3...HEAD
[0.2.3]: https://github.com/dasomel/kube-ready-box/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/dasomel/kube-ready-box/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/dasomel/kube-ready-box/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/dasomel/kube-ready-box/compare/v0.1.3...v0.2.0
[0.1.3]: https://github.com/dasomel/kube-ready-box/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/dasomel/kube-ready-box/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/dasomel/kube-ready-box/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/dasomel/kube-ready-box/releases/tag/v0.1.0
