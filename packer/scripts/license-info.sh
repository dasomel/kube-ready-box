#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 dasomel
set -e

echo "=== license-info.sh: Installing License Information ==="

# Box 정보 파일 생성
mkdir -p /etc/vagrant-box

cat <<'EOF' > /etc/vagrant-box/info.txt
===============================================
  dasomel/ubuntu-24.04 Vagrant Box
===============================================

Box Name:     dasomel/ubuntu-24.04
Base OS:      Ubuntu 24.04 LTS (Cloud Image)
Purpose:      Kubernetes-ready optimized OS
License:      MIT License

Source:       https://github.com/dasomel/kube-ready-box
Box URL:      https://app.vagrantup.com/dasomel/boxes/ubuntu-24.04

===============================================
  Pre-installed Optimizations
===============================================

1. Kernel tuning for K8s workloads
2. Network performance optimization
3. Disk I/O tuning
4. Resource limits configured
5. Swap disabled
6. Required kernel modules enabled

===============================================
  NOT Included (User Installation Required)
===============================================

- Container Runtime (containerd, CRI-O)
- Kubernetes (kubeadm, kubelet, kubectl)
- CNI Plugin (Cilium, Flannel, Calico, etc.)

===============================================
  License Information
===============================================

This Vagrant Box is distributed under the MIT License.

Copyright (c) 2025 dasomel <dasomell@gmail.com>

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.

===============================================
  Third-Party Components
===============================================

Ubuntu 24.04 LTS: https://ubuntu.com/
  License: Various (see /usr/share/doc/*/copyright)

For complete SBOM and dependency information, visit:
https://github.com/dasomel/kube-ready-box

===============================================

To view this information again: cat /etc/vagrant-box/info.txt

EOF

# motd 설정 (로그인 시 표시)
cat <<'EOF' > /etc/update-motd.d/99-vagrant-box-info
#!/bin/sh
cat <<'MOTD'

╔══════════════════════════════════════════════╗
║   dasomel/ubuntu-24.04 - K8s Ready OS        ║
║   Ubuntu 24.04 LTS + K8s Optimizations       ║
╚══════════════════════════════════════════════╝

📦 Box Info: cat /etc/vagrant-box/info.txt
📚 K8s Setup Guide: https://kubernetes.io/docs/setup/

MOTD
EOF

chmod +x /etc/update-motd.d/99-vagrant-box-info

echo "License information installed to /etc/vagrant-box/info.txt"
echo ""
echo "=== license-info.sh: Complete ==="
