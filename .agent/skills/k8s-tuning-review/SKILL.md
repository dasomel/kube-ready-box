---
name: k8s-tuning-review
description: Review Kubernetes node optimization settings including sysctl parameters, resource limits, disk/network tuning, and kernel configurations when reviewing OS tuning scripts or K8s preparation
---

# Kubernetes Node Tuning Review

Comprehensive review of OS-level optimizations for Kubernetes nodes, ensuring production-ready performance and stability.

## Instructions

When reviewing K8s node tuning scripts or configurations, verify the following:

### 1. Mandatory Prerequisites

#### Swap Configuration (CRITICAL)
```bash
# Must be disabled for K8s
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab
echo "vm.swappiness = 0" >> /etc/sysctl.d/k8s.conf
```

**Check**:
- [ ] Swap disabled in current session
- [ ] Swap removed from /etc/fstab
- [ ] vm.swappiness = 0 set

#### Required Kernel Modules
```bash
# /etc/modules-load.d/k8s.conf
overlay        # Container filesystem
br_netfilter   # Bridge network filtering
```

**Check**:
- [ ] Modules load on boot
- [ ] Modules currently loaded (`lsmod | grep -E "overlay|br_netfilter"`)

#### IP Forwarding (CRITICAL)
```bash
# /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
```

**Check**:
- [ ] All three parameters set to 1
- [ ] Applied with `sysctl --system`

### 2. Network Tuning

#### Connection Queue Limits
```bash
# /etc/sysctl.d/99-k8s-tuning.conf
net.core.somaxconn = 65535              # Socket backlog (default: 4096)
net.core.netdev_max_backlog = 65535     # Network device backlog
net.ipv4.tcp_max_syn_backlog = 65535    # SYN queue size
```

**Validation**:
- [ ] Values >= 32768 for production
- [ ] No warnings in `dmesg` about queue overflows

#### TCP Buffer Sizes
```bash
# 16MB buffers for high-throughput
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 262144
net.core.wmem_default = 262144

# TCP memory tuning (min, default, max in bytes)
net.ipv4.tcp_rmem = 4096 262144 16777216
net.ipv4.tcp_wmem = 4096 262144 16777216
```

**Guidelines**:
- 16MB max for high-bandwidth workloads
- 4MB adequate for standard workloads
- Match rmem and wmem settings

#### TCP Connection Management
```bash
# Reduce TIME_WAIT duration
net.ipv4.tcp_fin_timeout = 15           # Default: 60

# Reuse TIME_WAIT sockets
net.ipv4.tcp_tw_reuse = 1               # Safe for K8s

# Keepalive settings (K8s 1.29+ safe sysctls)
net.ipv4.tcp_keepalive_time = 300       # 5 minutes
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15

# MTU path discovery
net.ipv4.tcp_mtu_probing = 1
```

**Warnings**:
- [ ] Do NOT set `tcp_tw_recycle = 1` (unsafe, deprecated)
- [ ] Verify keepalive settings match K8s version

#### ARP Cache (Large Clusters)
```bash
# Scale ARP table for 100+ nodes
net.ipv4.neigh.default.gc_thresh1 = 4096
net.ipv4.neigh.default.gc_thresh2 = 8192
net.ipv4.neigh.default.gc_thresh3 = 16384
```

**When to adjust**:
- Clusters with 50+ nodes
- Symptom: "neighbour table overflow" in logs

#### Connection Tracking
```bash
# Essential for kube-proxy iptables mode
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_tcp_timeout_established = 86400
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 3600
```

**Sizing guide**:
- Small cluster (<10 nodes): 131072
- Medium cluster (10-50 nodes): 524288
- Large cluster (50+ nodes): 1048576
- Symptom: "nf_conntrack: table full" logs

### 3. Memory Management

#### Core Settings
```bash
vm.swappiness = 0                       # CRITICAL: No swap
vm.overcommit_memory = 1                # Allow overcommit (K8s needs)
vm.panic_on_oom = 0                     # Don't panic, let K8s handle
```

**Check**:
- [ ] swappiness = 0 (mandatory)
- [ ] overcommit_memory = 1 (required for container fork)
- [ ] panic_on_oom = 0 (let K8s evict pods)

#### Dirty Page Management
```bash
# I/O intensive workloads
vm.dirty_ratio = 40                     # Default: 20
vm.dirty_background_ratio = 10          # Default: 10
```

**Tuning**:
- Higher ratio = more memory cache before writeback
- Lower ratio = more frequent disk writes (safer)
- Adjust based on workload (database vs. web)

#### Kernel Memory
```bash
vm.min_free_kbytes = 131072             # 128MB reserved
```

**Sizing**:
- 1-4GB RAM: 65536 (64MB)
- 4-16GB RAM: 131072 (128MB)
- 16GB+ RAM: 262144 (256MB)

### 4. File System Limits

#### File Descriptors
```bash
fs.file-max = 2097152                   # System-wide limit

# /etc/security/limits.d/k8s.conf
* soft nofile 1048576
* hard nofile 1048576
```

**Validation**:
- [ ] `cat /proc/sys/fs/file-max` >= 2097152
- [ ] `ulimit -n` >= 1048576 (after login)

#### inotify Watches (CRITICAL for containers)
```bash
fs.inotify.max_user_watches = 524288    # Default: 8192 (too low!)
fs.inotify.max_user_instances = 8192    # Default: 128
```

**Why critical**:
- Each container can monitor files (logs, configs)
- Low limit causes "too many open files" errors
- Symptom: Pods fail to start with inotify errors

#### Process Limits
```bash
kernel.pid_max = 4194304                # Default: 32768

# /etc/security/limits.d/k8s.conf
* soft nproc 65535
* hard nproc 65535
```

**Sizing**:
- Allow for 100s-1000s of containers
- Each container can spawn multiple processes

### 5. Disk I/O Tuning

#### I/O Scheduler
```bash
# For SSD/NVMe (no mechanical seeking)
echo "none" > /sys/block/sda/queue/scheduler
echo "none" > /sys/block/nvme0n1/queue/scheduler

# For HDD (keep default mq-deadline or cfq)
```

**Check**:
- [ ] SSD/NVMe use 'none' or 'noop'
- [ ] HDD use 'mq-deadline' or 'cfq'
- [ ] Applied at boot (udev rules or rc.local)

#### Read-Ahead
```bash
# SSD: 256-512 KB
echo "256" > /sys/block/sda/queue/read_ahead_kb

# HDD: 1024-4096 KB
echo "2048" > /sys/block/sda/queue/read_ahead_kb
```

#### Filesystem Mount Options
```bash
# /etc/fstab optimization (ext4 example)
UUID=xxx / ext4 defaults,noatime,nodiratime,errors=remount-ro 0 1
```

**Options**:
- `noatime`: Don't update access time (performance++)
- `nodiratime`: Don't update directory access time
- `discard`: Enable TRIM for SSD (or use fstrim cron)

### 6. Network Interface Tuning

#### Ring Buffers
```bash
# Maximize RX/TX ring buffers
ethtool -G eth0 rx 4096 tx 4096
```

#### Offloading
```bash
# Enable TCP/UDP offloading
ethtool -K eth0 tso on gso on gro on
```

#### Interrupt Coalescing
```bash
# Reduce interrupt rate
ethtool -C eth0 rx-usecs 50 tx-usecs 50
```

**Persistence**: Add to network interface config or systemd service

### 7. Ubuntu 24.04 Specific

#### CPU Scheduler (Low Latency)
```bash
# /etc/sysctl.d/99-ubuntu2404-tuning.conf
kernel.sched_min_granularity_ns = 1000000    # 1ms (default: 3ms)
kernel.sched_wakeup_granularity_ns = 500000  # 0.5ms
```

**Use case**: Latency-sensitive workloads (real-time, gaming)

#### Transparent Huge Pages (THP)
```bash
# Database workloads: disable
echo 'never' > /sys/kernel/mm/transparent_hugepage/enabled
echo 'never' > /sys/kernel/mm/transparent_hugepage/defrag

# General workloads: madvise (app decides)
echo 'madvise' > /sys/kernel/mm/transparent_hugepage/enabled
echo 'madvise' > /sys/kernel/mm/transparent_hugepage/defrag
```

**Recommendation**:
- Databases (MySQL, MongoDB): `never`
- General K8s workloads: `madvise`

#### systemd-oomd
```bash
# Disable (K8s has its own OOM handling)
systemctl disable --now systemd-oomd
```

**Reason**: K8s eviction manager conflicts with systemd-oomd

#### journald Log Size
```bash
# /etc/systemd/journald.conf.d/size-limit.conf
[Journal]
SystemMaxUse=500M
SystemKeepFree=1G
MaxRetentionSec=1week
```

**Prevents**: Disk fill from excessive logs

### 8. Review Checklist

```
## Prerequisites (CRITICAL)
- [ ] Swap disabled (/proc/swaps empty)
- [ ] IP forwarding enabled
- [ ] Required kernel modules loaded
- [ ] Container runtime compatible (systemd cgroup driver)

## Network Tuning
- [ ] Connection queue limits appropriate
- [ ] TCP buffers sized correctly
- [ ] conntrack table sized for cluster
- [ ] MTU path discovery enabled

## Memory Management
- [ ] vm.swappiness = 0
- [ ] vm.overcommit_memory = 1
- [ ] Dirty page ratios appropriate
- [ ] min_free_kbytes set

## File System
- [ ] fs.file-max >= 2097152
- [ ] inotify.max_user_watches >= 524288
- [ ] Process limits adequate
- [ ] nofile limits set

## Disk I/O
- [ ] I/O scheduler matches disk type
- [ ] Read-ahead optimized
- [ ] noatime in fstab

## Network Interface
- [ ] Ring buffers maximized
- [ ] Offloading enabled
- [ ] Persistent configuration

## Ubuntu 24.04
- [ ] THP configured for workload
- [ ] systemd-oomd disabled
- [ ] journald size limited
```

### 9. Output Format

```
## CRITICAL Issues
- [script:line] Missing swap disable
  Fix:
  ```bash
  swapoff -a
  sed -i '/swap/d' /etc/fstab
  ```

## Warnings
- [sysctl.conf:15] inotify.max_user_watches too low (8192)
  Recommended: 524288
  Impact: Pods may fail to start with inotify errors

## Optimizations
- [disk-tuning.sh:10] Consider higher read-ahead for HDD
  Current: 256
  Suggested: 2048 (for HDD workloads)
```

### 10. Node Role Sizing

| Role | CPU | RAM | Disk | Key Tuning |
|------|-----|-----|------|------------|
| Master (small) | 2 | 4GB | 50GB | conntrack: 131072 |
| Master (medium) | 4 | 8GB | 100GB | conntrack: 524288 |
| Master (large) | 8 | 16GB | 200GB | conntrack: 1048576 |
| Worker (general) | 4 | 8GB | 100GB | Standard tuning |
| Worker (memory) | 8+ | 32GB+ | 500GB+ | min_free_kbytes: 262144 |

## Examples

### Example 1: Missing Critical Setting
```
## CRITICAL Issues
- [04-k8s-prereq.sh:15] IP forwarding not enabled
  Current: net.ipv4.ip_forward = 0
  Fix: Add to /etc/sysctl.d/k8s.conf
  ```
  net.ipv4.ip_forward = 1
  ```
  Apply: sysctl --system
```

### Example 2: Undersized for Cluster
```
## Warnings
- [02-os-tuning.sh:25] conntrack table too small for 50-node cluster
  Current: net.netfilter.nf_conntrack_max = 65536
  Recommended: 1048576
  Symptom: "nf_conntrack: table full" in dmesg
```

### Example 3: Disk Optimization
```
## Optimizations
- [05-disk-tuning.sh:10] I/O scheduler suboptimal for SSD
  Current: mq-deadline
  Recommended: none (for SSD/NVMe)
  ```bash
  echo "none" > /sys/block/sda/queue/scheduler
  ```
```

## Reference

- [Kubernetes sysctl Safe List](https://kubernetes.io/docs/tasks/administer-cluster/sysctl-cluster/)
- [Ubuntu 24.04 Kernel Tuning](https://discourse.ubuntu.com/t/fine-tuning-the-ubuntu-24-04-kernel-for-low-latency-throughput-and-power-efficiency/44834)
- [K8s Production Best Practices](https://learnk8s.io/production-best-practices)
- [Linux Performance Tuning](https://www.brendangregg.com/linuxperf.html)
