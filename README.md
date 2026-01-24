[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Vagrant Cloud](https://img.shields.io/badge/Vagrant-Cloud-blue)](https://app.vagrantup.com/dasomel/boxes/ubuntu-24.04)

**Languages**: [English](README.md) | [한국어](README.ko.md)

Kubernetes-ready Ubuntu 24.04 LTS Vagrant Box with OS-level optimizations.

> **Vagrant Cloud**: `dasomel/ubuntu-24.04`

## Features

- **Base OS**: Ubuntu 24.04 LTS Cloud Image
- **Multi-Architecture**: AMD64, ARM64
- **Multi-Provider**: VirtualBox, VMware Fusion
- **K8s Ready**: OS tuning for Kubernetes (K8s not included)

### Build Matrix

| Provider | AMD64 | ARM64 | Notes |
|----------|-------|-------|-------|
| VirtualBox | ✅ | ✅ | VirtualBox 7.1+ required for ARM64 |
| VMware Fusion | ✅ | ✅ | Apple Silicon supported |

## Quick Start

### Installation

```bash
# VirtualBox (auto-detect architecture)
vagrant init dasomel/ubuntu-24.04
vagrant up

# VMware Fusion
vagrant init dasomel/ubuntu-24.04
vagrant up --provider=vmware_desktop
```

### Vagrantfile Example

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "dasomel/ubuntu-24.04"

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

- **Kernel Parameters**: Network, memory, and filesystem tuning
- **Resource Limits**: File descriptors, processes, memory locks
- **K8s Prerequisites**: Swap disabled, kernel modules, IP forwarding
- **Disk I/O**: Scheduler and read-ahead optimization
- **Network**: TCP buffers, conntrack, ring buffers

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

- [Box Usage Guide](usage.md) - Detailed usage instructions
- [K8s Post-Install](k8s-post-install.md) - containerd/kubelet tuning
- [Packer Build Guide](packer/README.md) - Building boxes from source
- [Vagrant Cloud Guide](VAGRANT_CLOUD.md) - Upload, manage, and delete boxes
- [Legal & Licensing](legal.md) - OSS licenses and compliance
- [Changelog](CHANGELOG.md) - Release notes and version history

## Building from Source

```bash
cd packer

# Initialize Packer plugins
./build.sh init

# Build specific box
./build.sh vmware-arm64      # VMware ARM64
./build.sh virtualbox-arm64  # VirtualBox ARM64

# Build all boxes (4 boxes)
./build.sh all
```

## Requirements

### For Using the Box

- Vagrant 2.3+
- VirtualBox 7.1+ (for ARM64) or VMware Fusion

### For Building from Source

- Packer 1.8+
- VirtualBox 7.1+ / VMware Fusion
- 20GB+ disk space per box

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

### Third-Party Licenses

This box includes software from various open source projects. See [NOTICE](NOTICE) for details.

| Component | License |
|-----------|---------|
| Ubuntu 24.04 | [Various](https://ubuntu.com/legal/open-source-licences) |
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

- [Vagrant Cloud](https://app.vagrantup.com/dasomel/boxes/ubuntu-24.04)
- [GitHub Repository](https://github.com/dasomel/kube-ready-box)
- [Issue Tracker](https://github.com/dasomel/kube-ready-box/issues)
