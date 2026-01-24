# kube-ready-box

Ubuntu 24.04 Cloud-based multi-architecture (ARM/AMD64) optimized OS for Kubernetes installation

> GitHub: https://github.com/dasomel/kube-ready-box
> Vagrant Cloud: https://app.vagrantup.com/dasomel/boxes/ubuntu-24.04

## 1. Box Overview

| Item | Description |
|------|-------------|
| Base OS | Ubuntu 24.04 LTS Cloud Image |
| Architecture | AMD64, ARM64 |
| Provider | VirtualBox, VMware Fusion |
| Purpose | Optimized OS for Kubernetes installation (K8s not included) |

### Build Matrix

| Provider | AMD64 | ARM64 | Notes |
|----------|-------|-------|-------|
| VirtualBox | O | O | VirtualBox 7.1+ required (ARM64) |
| VMware Fusion | O | O | |

> **Note**: VirtualBox 7.1+ supports ARM64 guests on Apple Silicon (M1/M2/M3/M4).
> [VirtualBox 7.1 ARM64 Support Announcement](https://cjones-oracle.medium.com/virtualbox-7-1-supports-macos-arm64-hosts-280d02130c02)

### Base Images (Ubuntu Cloud Images)

| Architecture | ISO/Image URL |
|--------------|---------------|
| AMD64 | https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img |
| ARM64 | https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-arm64.img |

> **Note**: Built directly with Packer based on official Ubuntu Cloud Images.
> [Ubuntu Cloud Images](https://cloud-images.ubuntu.com/)

Total 4 Box builds:
- `dasomel/ubuntu-24.04` (virtualbox, amd64)
- `dasomel/ubuntu-24.04` (virtualbox, arm64)
- `dasomel/ubuntu-24.04` (vmware_desktop, amd64)
- `dasomel/ubuntu-24.04` (vmware_desktop, arm64)

> Vagrant Cloud manages builds for each Provider/Architecture combination under a single Box name.

## 2. Multi-Architecture Build

### Packer Template Structure
```
packer/
├── virtualbox-amd64.pkr.hcl    # VirtualBox AMD64
├── virtualbox-arm64.pkr.hcl    # VirtualBox ARM64 (VirtualBox 7.1+)
├── vmware-amd64.pkr.hcl        # VMware AMD64
├── vmware-arm64.pkr.hcl        # VMware ARM64 (Apple Silicon)
├── variables.pkr.hcl
├── http/
│   └── user-data
└── scripts/
    ├── 01-base.sh           # Package updates
    ├── 02-os-tuning.sh      # OS kernel/resource tuning
    ├── 03-os-packages.sh    # Recommended packages installation
    ├── 04-k8s-prereq.sh     # K8s prerequisites (runtime excluded)
    ├── 05-disk-tuning.sh    # Disk I/O optimization
    ├── 06-nic-tuning.sh     # Network optimization
    ├── 07-check-tuning.sh   # Configuration verification
    ├── 99-cleanup.sh        # Pre-deployment cleanup
    └── 99-license-audit.sh  # License audit
```

### Packer Build Provisioner Configuration
```hcl
build {
  sources = ["source.virtualbox-iso.ubuntu-vbox-amd64"]

  # Sequential script execution (order matters)
  provisioner "shell" {
    scripts = [
      "scripts/01-base.sh",
      "scripts/02-os-tuning.sh",
      "scripts/03-os-packages.sh",
      "scripts/04-k8s-prereq.sh",
      "scripts/05-disk-tuning.sh",
      "scripts/06-nic-tuning.sh",
      "scripts/07-check-tuning.sh",
      "scripts/99-cleanup.sh"
    ]
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  }

  # Vagrant Box creation
  post-processor "vagrant" {
    output = "ubuntu-24.04-virtualbox-amd64.box"
  }
}
```

### Cloud-Init Configuration (http/user-data)
```yaml
#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: k8s-node
    username: vagrant
    password: "$6$rounds=4096$..."  # vagrant
  ssh:
    install-server: true
    allow-pw: true
  packages:
    - open-vm-tools
    - cloud-init
  late-commands:
    - echo 'vagrant ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/vagrant
```

### VirtualBox AMD64
```hcl
source "virtualbox-iso" "ubuntu-vbox-amd64" {
  iso_url           = "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
  iso_checksum      = "file:https://cloud-images.ubuntu.com/releases/24.04/release/SHA256SUMS"
  vm_name           = "ubuntu-24.04-virtualbox-amd64"
  guest_os_type     = "Ubuntu_64"
  cpus              = 2
  memory            = 2048
  disk_size         = 20000
  ssh_username      = "vagrant"
  ssh_password      = "vagrant"
  shutdown_command  = "sudo shutdown -P now"
  http_directory    = "http"
  boot_command      = [
    "<wait>",
    "autoinstall ds=nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/",
    "<enter>"
  ]
}
```

### VirtualBox ARM64 (VirtualBox 7.1+)
```hcl
source "virtualbox-iso" "ubuntu-vbox-arm64" {
  iso_url           = "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-arm64.img"
  iso_checksum      = "file:https://cloud-images.ubuntu.com/releases/24.04/release/SHA256SUMS"
  vm_name           = "ubuntu-24.04-virtualbox-arm64"
  guest_os_type     = "Ubuntu_arm64"
  cpus              = 2
  memory            = 2048
  disk_size         = 20000
  ssh_username      = "vagrant"
  ssh_password      = "vagrant"
  shutdown_command  = "sudo shutdown -P now"
  http_directory    = "http"
  boot_command      = [
    "<wait>",
    "autoinstall ds=nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/",
    "<enter>"
  ]
}
```

### VMware Fusion AMD64
```hcl
source "vmware-iso" "ubuntu-vmware-amd64" {
  iso_url           = "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
  iso_checksum      = "file:https://cloud-images.ubuntu.com/releases/24.04/release/SHA256SUMS"
  vm_name           = "ubuntu-24.04-vmware-amd64"
  guest_os_type     = "ubuntu-64"
  cpus              = 2
  memory            = 2048
  disk_size         = 20000
  ssh_username      = "vagrant"
  ssh_password      = "vagrant"
  shutdown_command  = "sudo shutdown -P now"
  http_directory    = "http"
  vmx_data = {
    "ethernet0.virtualdev" = "vmxnet3"
  }
}
```

### VMware Fusion ARM64
```hcl
source "vmware-iso" "ubuntu-vmware-arm64" {
  iso_url           = "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-arm64.img"
  iso_checksum      = "file:https://cloud-images.ubuntu.com/releases/24.04/release/SHA256SUMS"
  vm_name           = "ubuntu-24.04-vmware-arm64"
  guest_os_type     = "arm-ubuntu-64"
  cpus              = 2
  memory            = 2048
  disk_size         = 20000
  ssh_username      = "vagrant"
  ssh_password      = "vagrant"
  shutdown_command  = "sudo shutdown -P now"
  http_directory    = "http"
  vmx_data = {
    "ethernet0.virtualdev" = "vmxnet3"
  }
}
```

### Build Execution
```bash
# Individual builds
packer build -only=virtualbox-iso.ubuntu-vbox-amd64 .   # VirtualBox AMD64
packer build -only=virtualbox-iso.ubuntu-vbox-arm64 .   # VirtualBox ARM64 (7.1+)
packer build -only=vmware-iso.ubuntu-vmware-amd64 .     # VMware AMD64
packer build -only=vmware-iso.ubuntu-vmware-arm64 .     # VMware ARM64

# Build by provider
packer build -only='virtualbox-iso.*' .  # VirtualBox (AMD64 + ARM64)
packer build -only='vmware-iso.*' .      # VMware (AMD64 + ARM64)

# Full build (all 4)
packer build .
```

### Packer Build Best Practices

> Reference: [HashiCorp Packer Documentation](https://developer.hashicorp.com/packer/docs), [geerlingguy/packer-boxes](https://github.com/geerlingguy/packer-boxes)

#### 1. Use HCL Format (instead of JSON)
```bash
# JSON to HCL conversion
packer hcl2_upgrade -output-file=template.pkr.hcl template.json
```

#### 2. Headless Build (without GUI)
```hcl
source "virtualbox-iso" "ubuntu" {
  headless = true  # Required for CI/CD pipelines
  # ...
}
```

#### 3. Guest Additions Version Management
```bash
# Update Guest Additions when VirtualBox updates
# Box rebuild recommended
VBOX_VERSION=$(VBoxManage --version | cut -d'r' -f1)
```

#### 4. Output Compression Settings
```hcl
post-processor "vagrant" {
  output               = "{{.BuildName}}.box"
  compression_level    = 9  # Maximum compression (for distribution)
  keep_input_artifact  = false
}
```

#### 5. Separate Variable Files
```hcl
# variables.pkr.hcl
variable "iso_url" {
  type    = string
  default = "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
}

variable "ssh_username" {
  type    = string
  default = "vagrant"
}

variable "ssh_password" {
  type      = string
  default   = "vagrant"
  sensitive = true
}
```

#### 6. Parallel Build Configuration
```bash
# Limit concurrent builds (resource management)
packer build -parallel-builds=2 .
```

#### 7. Utilize Cache and Checksum
```hcl
source "virtualbox-iso" "ubuntu" {
  iso_url      = var.iso_url
  iso_checksum = "file:https://cloud-images.ubuntu.com/releases/24.04/release/SHA256SUMS"
  # Packer automatically caches and verifies
}
```

## 3. Base Package Updates

### scripts/base.sh
```bash
#!/bin/bash
set -e

# Package updates
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get dist-upgrade -y

# Install essential packages
sudo apt-get install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  software-properties-common

# Disable automatic updates (K8s stability)
sudo systemctl disable --now unattended-upgrades
sudo apt-get remove -y unattended-upgrades

# Remove unnecessary packages
sudo apt-get autoremove -y
sudo apt-get clean
```

## 4. Kubernetes Installation Prerequisites

> **Note**: This Box includes only OS optimization for K8s installation.
> Users install the required K8s version themselves.

### scripts/04-k8s-prereq.sh
```bash
#!/bin/bash
set -e

#=========================================
# K8s Prerequisites (runtime/components excluded)
#=========================================

# Disable swap (K8s required)
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab
echo "vm.swappiness = 0" | sudo tee -a /etc/sysctl.d/k8s-prereq.conf

# Load required kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Required network settings
cat <<EOF | sudo tee /etc/sysctl.d/k8s-network.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# Basic packages required for K8s installation
sudo apt-get update
sudo apt-get install -y \
  socat \
  conntrack \
  ipset \
  ipvsadm \
  ebtables

# Prepare apt keyring directory (for K8s repository)
sudo mkdir -p /etc/apt/keyrings

echo "=== K8s Prerequisites Configured ==="
echo "User should install the following in next steps:"
echo "  1. Container runtime (containerd, CRI-O, etc.)"
echo "  2. kubeadm, kubelet, kubectl"
echo "  3. CNI plugins"
```

### Components to Install by User

After using the Box, users selectively install:

| Component | Description | Installation Guide |
|-----------|-------------|-------------------|
| containerd | Container runtime | https://containerd.io/docs/getting-started/ |
| CRI-O | Container runtime (alternative) | https://cri-o.io/ |
| kubeadm | Cluster bootstrap | https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/ |
| kubelet | Node agent | Install according to K8s version |
| kubectl | CLI tool | Install according to K8s version |

### K8s Installation Example (after using Box)
```bash
# 1. Install containerd
sudo apt-get update
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# 2. Add K8s repository (choose your version)
K8S_VERSION="v1.31"  # or v1.30, v1.29, etc.
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key" | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

# 3. Install kubeadm, kubelet, kubectl
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable kubelet
```

## 5. OS Optimization and Tuning

> **Reference**: Based on [Kubernetes Official Documentation](https://kubernetes.io/docs/tasks/administer-cluster/sysctl-cluster/),
> [Ubuntu 24.04 Kernel Tuning Guide](https://discourse.ubuntu.com/t/fine-tuning-the-ubuntu-24-04-kernel-for-low-latency-throughput-and-power-efficiency/44834),
> [K8s Kernel Tuning Best Practices](https://overcast.blog/kernel-tuning-and-optimization-for-kubernetes-a-guide-a3bdc8f7d255)

### scripts/os-tuning.sh
```bash
#!/bin/bash
set -e

#=========================================
# 1. Kernel Parameter Optimization
#=========================================
cat <<EOF | sudo tee /etc/sysctl.d/99-k8s-tuning.conf
#-----------------------------------------
# Network Performance Optimization
#-----------------------------------------
# Socket connection queue (default 4096 -> 65535)
# Increase needed in container environments with hundreds of concurrent processes
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535

# TCP buffer size (16MB) - for high bandwidth workloads
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 262144
net.core.wmem_default = 262144

# TCP memory settings (min, default, max)
net.ipv4.tcp_rmem = 4096 262144 16777216
net.ipv4.tcp_wmem = 4096 262144 16777216

# TCP connection management
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15

# TCP Keepalive (K8s 1.29+ safe sysctl)
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15

# Enable MTU discovery
net.ipv4.tcp_mtu_probing = 1

#-----------------------------------------
# Memory Management
#-----------------------------------------
# No swap (K8s required)
vm.swappiness = 0

# Allow memory overcommit (needed for fork)
vm.overcommit_memory = 1

# Prevent panic on OOM
vm.panic_on_oom = 0

# Dirty page management (I/O intensive workloads)
vm.dirty_ratio = 40
vm.dirty_background_ratio = 10

# Minimum free memory (for kernel allocation)
vm.min_free_kbytes = 131072

#-----------------------------------------
# File System
#-----------------------------------------
# Maximum file descriptors
fs.file-max = 2097152

# inotify limits (essential for container environments)
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 8192

# Maximum processes/namespaces
kernel.pid_max = 4194304

#-----------------------------------------
# ARP Cache Optimization (large clusters)
#-----------------------------------------
net.ipv4.neigh.default.gc_thresh1 = 4096
net.ipv4.neigh.default.gc_thresh2 = 8192
net.ipv4.neigh.default.gc_thresh3 = 16384

#-----------------------------------------
# conntrack Optimization (many services/pods)
#-----------------------------------------
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_tcp_timeout_established = 86400
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 3600
EOF

sudo sysctl --system

#=========================================
# 2. Resource Limits Configuration
#=========================================
cat <<EOF | sudo tee /etc/security/limits.d/k8s.conf
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 65535
* hard nproc 65535
* soft memlock unlimited
* hard memlock unlimited
EOF

# Note: containerd/kubelet service limits are set after K8s installation
# Below is for reference after K8s installation (not included in Box)
# sudo mkdir -p /etc/systemd/system/containerd.service.d
# See /etc/systemd/system/containerd.service.d/limits.conf
```

### Recommended OS Packages
```bash
#!/bin/bash
# scripts/os-packages.sh

# Essential packages
sudo apt-get install -y \
  linux-tools-common \
  linux-tools-generic \
  sysstat \
  iotop \
  iftop \
  nload \
  nethogs \
  dstat

# Network diagnostic tools
sudo apt-get install -y \
  ipvsadm \
  ipset \
  conntrack \
  ethtool \
  tcpdump \
  nmap

# Performance analysis tools
sudo apt-get install -y \
  linux-tools-$(uname -r) \
  bpfcc-tools \
  bpftrace
```

### Disk I/O Optimization
```bash
#!/bin/bash
# scripts/disk-tuning.sh

# I/O scheduler settings (for SSD)
for disk in /sys/block/sd*/queue/scheduler; do
  echo "none" | sudo tee $disk 2>/dev/null || true
done

for disk in /sys/block/nvme*/queue/scheduler; do
  echo "none" | sudo tee $disk 2>/dev/null || true
done

# Read-ahead settings
for disk in /sys/block/sd*/queue/read_ahead_kb; do
  echo "256" | sudo tee $disk 2>/dev/null || true
done

# Journaling optimization (ext4)
# Recommend adding noatime,nodiratime options to fstab
```

### Network Interface Optimization
```bash
#!/bin/bash
# scripts/nic-tuning.sh

INTERFACE="eth0"  # Main interface

# Maximize ring buffer
sudo ethtool -G $INTERFACE rx 4096 tx 4096 2>/dev/null || true

# Enable offloading
sudo ethtool -K $INTERFACE tso on gso on gro on 2>/dev/null || true

# Interrupt coalescing
sudo ethtool -C $INTERFACE rx-usecs 50 tx-usecs 50 2>/dev/null || true
```

### Tuning Checklist

| Item | Default | Recommended | Description |
|------|---------|-------------|-------------|
| vm.swappiness | 60 | 0 | K8s requires swap disabled |
| vm.dirty_ratio | 20 | 40 | For I/O intensive workloads |
| vm.min_free_kbytes | 67584 | 131072 | Free memory for kernel allocation |
| fs.file-max | 1048576 | 2097152 | Maximum file descriptors |
| fs.inotify.max_user_watches | 8192 | 524288 | Essential for container environments |
| kernel.pid_max | 32768 | 4194304 | For large scale pods |
| net.core.somaxconn | 4096 | 65535 | Socket connection queue |
| net.core.rmem_max | 212992 | 16777216 | TCP receive buffer max |
| net.core.wmem_max | 212992 | 16777216 | TCP send buffer max |
| net.ipv4.ip_forward | 0 | 1 | IP forwarding (required) |
| net.ipv4.tcp_mtu_probing | 0 | 1 | Automatic MTU discovery |
| nf_conntrack_max | 65536 | 1048576 | Connection tracking table size |
| nofile (ulimit) | 1024 | 1048576 | File limit per process |

### Ubuntu 24.04 Specific Settings

Ubuntu 24.04 includes low-latency kernel tuning options in the default kernel.

```bash
#!/bin/bash
# scripts/ubuntu2404-tuning.sh

#=========================================
# Ubuntu 24.04 Specific Optimization
#=========================================

# Kernel scheduler tuning (low-latency options)
# Available in Ubuntu 24.04 generic kernel
cat <<EOF | sudo tee /etc/sysctl.d/99-ubuntu2404-tuning.conf
# Minimize scheduler latency
kernel.sched_min_granularity_ns = 1000000
kernel.sched_wakeup_granularity_ns = 500000

# Transparent Huge Pages (THP) settings
# Choose 'madvise' or 'never' depending on K8s workload
# Database workloads: never recommended
EOF

# THP settings (memory intensive workloads)
echo 'madvise' | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
echo 'madvise' | sudo tee /sys/kernel/mm/transparent_hugepage/defrag

# Disable systemd-oomd (use K8s eviction instead)
sudo systemctl disable --now systemd-oomd

# Limit journald log size (disk savings)
sudo mkdir -p /etc/systemd/journald.conf.d
cat <<EOF | sudo tee /etc/systemd/journald.conf.d/size-limit.conf
[Journal]
SystemMaxUse=500M
SystemKeepFree=1G
MaxRetentionSec=1week
EOF
sudo systemctl restart systemd-journald
```

### Recommended Specs by Node Role

| Role | CPU | Memory | Disk | Notes |
|------|-----|--------|------|-------|
| Master (small) | 2 | 4GB | 50GB | Up to 10 nodes |
| Master (medium) | 4 | 8GB | 100GB | Up to 100 nodes |
| Master (large) | 8 | 16GB | 200GB | 100+ nodes |
| Worker (general) | 4 | 8GB | 100GB | General workloads |
| Worker (high-perf) | 8+ | 32GB+ | 500GB+ | Memory intensive |

### Production Recommended Settings Verification
```bash
#!/bin/bash
# scripts/check-tuning.sh

echo "=== K8s Node Tuning Check ==="

echo -e "\n[1] Swap Status"
free -h | grep Swap

echo -e "\n[2] Kernel Parameters"
sysctl net.ipv4.ip_forward
sysctl vm.swappiness
sysctl fs.file-max
sysctl net.core.somaxconn

echo -e "\n[3] Resource Limits"
ulimit -n
ulimit -u

echo -e "\n[4] Kernel Modules"
lsmod | grep -E "overlay|br_netfilter"

echo -e "\n[5] Cgroup Driver"
cat /sys/fs/cgroup/cgroup.controllers 2>/dev/null || echo "cgroup v1"

echo -e "\n[6] Container Runtime (after K8s installation)"
systemctl is-active containerd 2>/dev/null || echo "Not installed (normal - user installs)"

echo -e "\n[7] kubelet (after K8s installation)"
systemctl is-active kubelet 2>/dev/null || echo "Not installed (normal - user installs)"

echo -e "\n=== K8s Ready OS Check Complete ==="
```

## 6. Vagrant Cloud Upload

### Upload 4 Boxes
```bash
# VirtualBox AMD64
vagrant cloud publish dasomel/ubuntu-24.04 0.1.0 \
  virtualbox ./ubuntu-24.04-virtualbox-amd64.box \
  --architecture amd64 \
  --release

# VirtualBox ARM64
vagrant cloud publish dasomel/ubuntu-24.04 0.1.0 \
  virtualbox ./ubuntu-24.04-virtualbox-arm64.box \
  --architecture arm64 \
  --release

# VMware Fusion AMD64
vagrant cloud publish dasomel/ubuntu-24.04 0.1.0 \
  vmware_desktop ./ubuntu-24.04-vmware-amd64.box \
  --architecture amd64 \
  --release

# VMware Fusion ARM64
vagrant cloud publish dasomel/ubuntu-24.04 0.1.0 \
  vmware_desktop ./ubuntu-24.04-vmware-arm64.box \
  --architecture arm64 \
  --release
```

### Automation Script (scripts/upload-all.sh)
```bash
#!/bin/bash
set -e

USERNAME="dasomel"
BOX_NAME="ubuntu-24.04"
VERSION="${1:-0.1.0}"

BOXES=(
  "virtualbox:amd64:ubuntu-24.04-virtualbox-amd64.box"
  "virtualbox:arm64:ubuntu-24.04-virtualbox-arm64.box"
  "vmware_desktop:amd64:ubuntu-24.04-vmware-amd64.box"
  "vmware_desktop:arm64:ubuntu-24.04-vmware-arm64.box"
)

for box in "${BOXES[@]}"; do
  IFS=':' read -r provider arch file <<< "$box"
  echo "Uploading $file ($provider, $arch)..."
  vagrant cloud publish "$USERNAME/$BOX_NAME" "$VERSION" \
    "$provider" "./$file" \
    --architecture "$arch" \
    --release
done

echo "All boxes uploaded successfully!"
```

## 7. OSS License

> See [legal.md](legal.md) for details

### Summary

| Item | Description |
|------|-------------|
| Recommended License | MIT (permissive), Apache 2.0 (patent protection) |
| Required Files | LICENSE, NOTICE, README |
| SBOM | Generate with syft or trivy |
| Legal Review | Check trademarks, patents, export regulations |

### Project Structure
```
project/
├── LICENSE                 # Full license text
├── NOTICE                  # Copyright and third-party notices
├── README.md               # Include license badge
└── packer/
    └── scripts/
        └── license-info.sh # Install license info in Box
```

## 8. Recommended Settings After K8s Installation

> See [k8s-post-install.md](k8s-post-install.md) for details

Recommended settings to apply after installing K8s:

- containerd optimization (config.toml, service resource limits)
- kubelet tuning (KubeletConfiguration)
- CNI configuration (Cilium, Flannel, Calico)
- kubectl completion and recommended tools (Helm, k9s, stern, etc.)

## 9. References

- [Ubuntu Cloud Images](https://cloud-images.ubuntu.com/)
- [Kubernetes Official Documentation](https://kubernetes.io/docs/)
- [kubeadm Installation Guide](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [Packer Documentation](https://developer.hashicorp.com/packer/docs)
- [Vagrant VMware Provider](https://developer.hashicorp.com/vagrant/docs/providers/vmware)
- [Choose a License](https://choosealicense.com/)
- [SPDX License List](https://spdx.org/licenses/)
