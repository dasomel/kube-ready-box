[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Build AMD64](https://github.com/dasomel/kube-ready-box/actions/workflows/build-amd64.yml/badge.svg)](https://github.com/dasomel/kube-ready-box/actions/workflows/build-amd64.yml)
[![Vagrant Cloud - 24.04 ext4](https://img.shields.io/badge/Vagrant-24.04--ext4-blue)](https://app.vagrantup.com/dasomel/boxes/ubuntu-24.04-ext4)
[![Vagrant Cloud - 24.04 xfs](https://img.shields.io/badge/Vagrant-24.04--xfs-green)](https://app.vagrantup.com/dasomel/boxes/ubuntu-24.04-xfs)
[![Vagrant Cloud - 26.04 ext4](https://img.shields.io/badge/Vagrant-26.04--ext4-blue)](https://app.vagrantup.com/dasomel/boxes/ubuntu-26.04-ext4)
[![Vagrant Cloud - 26.04 xfs](https://img.shields.io/badge/Vagrant-26.04--xfs-green)](https://app.vagrantup.com/dasomel/boxes/ubuntu-26.04-xfs)

**Languages**: [English](README.md) | [한국어](README.ko.md)

Kubernetes-ready Ubuntu Vagrant Box with OS-level optimizations. Supports **24.04 LTS** (Noble Numbat, default) and **26.04 LTS** (Resolute Raccoon, kernel Linux 7.0).

> **Vagrant Cloud (v1.1.0)**:
> - 24.04 ext4: `dasomel/ubuntu-24.04-ext4` / xfs: `dasomel/ubuntu-24.04-xfs`
> - 26.04 ext4: `dasomel/ubuntu-26.04-ext4` / xfs: `dasomel/ubuntu-26.04-xfs`

## 24.04 vs 26.04

| | 24.04 LTS (Noble Numbat) | 26.04 LTS (Resolute Raccoon) |
|---|---|---|
| Kernel | 6.8 | **7.0** |
| init / cgroup | systemd 255, cgroup v2 default | systemd 259, **cgroup v1 removed (v2-only)** |
| Container runtime | containerd 1.7 | containerd 2.2 / runc 1.4 |
| Crypto | TLS 1.2+ | **Post-quantum default** (OpenSSL 3.5 / OpenSSH 10.2) |
| Core utilities | GNU coreutils, sudo | partial Rust rewrite (uutils, sudo-rs) |
| Choose when | Maximum stability (**default**) | Latest LTS, kernel 7.0 features |

> **K8s note**: 26.04 is cgroup v2-only — set `SystemdCgroup=true` for kubelet/containerd (see [K8s Post-Install](docs/k8s-post-install.md)). Both lines are tuned identically for Kubernetes. Full comparison: [migration notes](docs/ubuntu-2604-migration/24-04-vs-26-04-comparison.md).

## Features

- **Base OS**: Ubuntu 24.04 LTS or 26.04 LTS Cloud Image
- **Multi-Architecture**: AMD64, ARM64
- **Multi-Provider**: VirtualBox, VMware Fusion
- **Filesystem Selection**: ext4 (default) or xfs
- **K8s Ready**: OS tuning for Kubernetes (K8s not included)
- **1TB Disk**: Large disk with thin provisioning (ext4 ~2.2GB, xfs ~3.4GB)
- **Auto-Extension**: Disk auto-extends on boot (partition → PV → LV → filesystem)

> **NixOS variant**: a declarative NixOS box is published separately as `dasomel/nixos-kube-ready` (libvirt / arm64 — also usable on Apple Silicon via `vagrant-qemu`). See [`nixos/`](nixos/).

### Build Matrix

| Provider | AMD64 | ARM64 | Notes |
|----------|-------|-------|-------|
| VirtualBox | ✅ | ✅ | VirtualBox 7.1+ required for ARM64 |
| VMware Fusion | ✅* | ✅ | Apple Silicon supported; *AMD64 is local-build only — Vagrant Cloud ships ARM64 (CI runner limitation) |

## Quick Start

### Installation

```bash
# 24.04 ext4 (default, stable, general purpose)
vagrant init dasomel/ubuntu-24.04-ext4
vagrant up --provider=vmware_desktop

# 24.04 xfs (better for K8s ephemeral storage quota, large files)
vagrant init dasomel/ubuntu-24.04-xfs
vagrant up --provider=vmware_desktop

# 26.04 (Resolute Raccoon, kernel Linux 7.0)
vagrant init dasomel/ubuntu-26.04-ext4
vagrant up --provider=vmware_desktop
```

### Filesystem Comparison

| | ext4 | xfs |
|---|---|---|
| **Best for** | General purpose | K8s workloads, large files |
| **K8s Quota** | No native support | `--local-storage-capacity-isolation` |
| **Online Shrink** | Supported | Not supported |
| **Box Size** | ~2.2GB | ~3.4GB |

### Vagrantfile Example

```ruby
Vagrant.configure("2") do |config|
  # 24.04: "dasomel/ubuntu-24.04-ext4" or "dasomel/ubuntu-24.04-xfs"
  # 26.04: "dasomel/ubuntu-26.04-ext4" or "dasomel/ubuntu-26.04-xfs"
  config.vm.box = "dasomel/ubuntu-24.04-ext4"

  config.vm.provider "virtualbox" do |vb|
    vb.memory = 4096
    vb.cpus = 2
  end

  config.vm.provider "vmware_desktop" do |v|
    v.vmx["memsize"] = "4096"
    v.vmx["numvcpus"] = "2"
  end

  config.vm.hostname = "k8s-node"
  config.vm.network "private_network", ip: "192.168.56.10"
end
```

## What's Included

### OS Optimizations

- **Kernel Parameters**: Network, memory, and filesystem tuning (`vm.max_map_count=1048576`)
- **Resource Limits**: File descriptors, processes, memory locks
- **K8s Prerequisites**: Swap disabled, required kernel modules (`br_netfilter`, `overlay`, `iscsi_tcp`), IP forwarding, persistent `bpffs` mount (`/sys/fs/bpf` for Cilium), CSI storage prerequisites (`open-iscsi` with `iscsid` enabled, `cryptsetup`, `dmsetup`, `nfs-common` for Longhorn V1)
- **Security & Compliance**: `unattended-upgrades` purged (kubelet Graceful Node Shutdown conflict), `needrestart` removed (Qualys LPE CVEs), `auditd` installed (disabled by default, CIS benchmark ready with bounded I/O settings)
- **Time Synchronization**: `chrony` replacing `systemd-timesyncd` (Ubuntu 25.10+/26.04 default, K8s/etcd recommended), Korean NTP servers configured via `/etc/chrony/sources.d/kr-ntp.sources`
- **Disk I/O**: Scheduler and read-ahead optimization
- **Network**: TCP buffers, conntrack, ring buffers, `dhcp-identifier: mac` netplan configuration (fixes 26.04 post-install IP change SSH timeout)

### Pre-installed Tools

| Category | Tools |
|----------|-------|
| **K8s Ecosystem** | jq, yq, bash-completion, nfs-common, open-iscsi, cryptsetup, dmsetup, apparmor-utils, sshpass |
| **Security & Audit** | auditd (disabled by default) |
| **Monitoring** | sysstat, iotop, iftop, nload, nethogs, dool |
| **Network Diag** | ipvsadm, ipset, conntrack, ethtool, tcpdump, nmap |
| **Performance** | linux-tools, bpfcc-tools, bpftrace |

### What's NOT Included

Users install these components based on their requirements:

- Container runtime (containerd, CRI-O)
- Kubernetes (kubeadm, kubelet, kubectl)
- CNI plugins (Flannel, Calico, Cilium)

## K8s Installation (After Box Setup)

```bash
# 1. Install containerd
sudo apt-get update && sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd && sudo systemctl enable containerd

# 2. Install K8s (choose your version)
K8S_VERSION="v1.31"
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key" | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update && sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# 3. Initialize cluster (master node)
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
```

## Verify Box Tuning

```bash
# Check tuning settings
vagrant ssh -c "cat /etc/vagrant-box/info.json"
vagrant ssh -c "/bin/bash /etc/vagrant-box/check-tuning.sh"
```

## Documentation

- [Box Usage Guide](docs/usage.md) - Detailed usage instructions
- [K8s Post-Install](docs/k8s-post-install.md) - containerd/kubelet tuning
- [Packer Build Guide](packer/README.md) - Building boxes from source
- [Vagrant Cloud Guide](docs/VAGRANT_CLOUD.md) - Upload, manage, and delete boxes
- [HCP Credentials Setup](docs/hcp-credentials.md) - Rotate HCP service principal keys
- [Deploy Checklist](docs/DEPLOY_CHECKLIST.md) - Pre-release verification
- [Legal & Licensing](docs/legal.md) - OSS licenses and compliance
- [Changelog](CHANGELOG.md) - Release notes and version history

## Building from Source

```bash
cd packer

# Initialize Packer plugins
./build.sh init

# Build 24.04 (default)
./build.sh vmware-arm64
./build.sh vmware-arm64 --fs=xfs

# Build 26.04
./build.sh vmware-arm64 --version=26.04
./build.sh vmware-arm64 --version=26.04 --fs=xfs

# Build all boxes
./build.sh all                         # 24.04 ext4
./build.sh all --version=26.04         # 26.04 ext4

# Upload (root script)
UBUNTU_VERSION=26.04 ./upload-boxes.sh # 26.04 upload
```

> **CI**: Use the `ubuntu_version` input in the GitHub Actions `workflow_dispatch` trigger to select 24.04 or 26.04.

## Requirements

### For Using the Box

- Vagrant 2.3+
- VirtualBox 7.1+ (for ARM64) or VMware Fusion

### For Building from Source

- Packer 1.10+ (CI pinned to 1.15.4)
- VirtualBox 7.1+ / VMware Fusion
- 20GB+ disk space per box
- Build timeouts: `ssh_timeout` 1h (2h for `vmware-arm64`), CI job timeout 90m

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

### Third-Party Licenses

This box includes software from various open source projects. See [NOTICE](NOTICE) for details.

| Component | License |
|-----------|---------|
| Ubuntu 24.04 / 26.04 | [Various](https://ubuntu.com/legal/open-source-licences) |
| Kubernetes | Apache 2.0 |
| containerd | Apache 2.0 |

## For AI-Assisted Development

This project includes comprehensive context files for AI coding assistants in the `.agent/` directory:

- **[AGENT.md](.agent/AGENT.md)** - Complete technical guide (Packer, K8s tuning, optimizations)
- **[SECURITY.md](.agent/SECURITY.md)** - Security guidelines and best practices
- **[skills/](.agent/skills/)** - AI agent skills for automated reviews

While designed for tools like [Claude Code](https://claude.ai/claude-code), these files contain valuable technical documentation for all developers working with Packer, Kubernetes, or Ubuntu optimization.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Links

- [Vagrant Cloud - 24.04 ext4](https://app.vagrantup.com/dasomel/boxes/ubuntu-24.04-ext4)
- [Vagrant Cloud - 24.04 xfs](https://app.vagrantup.com/dasomel/boxes/ubuntu-24.04-xfs)
- [Vagrant Cloud - 26.04 ext4](https://app.vagrantup.com/dasomel/boxes/ubuntu-26.04-ext4)
- [Vagrant Cloud - 26.04 xfs](https://app.vagrantup.com/dasomel/boxes/ubuntu-26.04-xfs)
- [GitHub Repository](https://github.com/dasomel/kube-ready-box)
- [Issue Tracker](https://github.com/dasomel/kube-ready-box/issues)
