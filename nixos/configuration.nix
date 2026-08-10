# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
#
# NixOS Kube-Ready Vagrant Box Configuration
# Pre-configured for Kubernetes (containerd, sysctl tuning, CSI prerequisites)

{ config, pkgs, modulesPath, ... }:

{
  imports = [
    # Support for standard VM guest additions and vagrant-generators formats
  ];

  # Allow unsupported packages (for ARM64 cross evaluation)
  nixpkgs.config.allowUnsupportedSystem = true;

  # Bootloader & Kernel Configuration
  boot.loader.grub.enable = pkgs.lib.mkDefault true;
  boot.loader.grub.device = pkgs.lib.mkDefault "/dev/sda";

  # K8s Required Kernel Modules
  boot.kernelModules = [
    "overlay"
    "br_netfilter"
    "iscsi_tcp"
  ];

  # K8s & High-Performance OS Sysctl Tuning
  boot.kernel.sysctl = {
    # Kubernetes Network Prerequisites
    "net.bridge.bridge-nf-call-iptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
    "net.ipv4.ip_forward" = 1;

    # IPv6 Disabling (K8s Recommended)
    "net.ipv6.conf.all.disable_ipv6" = 1;
    "net.ipv6.conf.default.disable_ipv6" = 1;
    "net.ipv6.conf.lo.disable_ipv6" = 1;

    # Network Socket & Buffer Optimization
    "net.core.somaxconn" = 65535;
    "net.core.netdev_max_backlog" = 65535;
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;
    "net.core.rmem_default" = 262144;
    "net.core.wmem_default" = 262144;
    "net.ipv4.tcp_rmem" = "4096 262144 16777216";
    "net.ipv4.tcp_wmem" = "4096 262144 16777216";
    "net.ipv4.tcp_max_syn_backlog" = 65535;
    "net.ipv4.tcp_tw_reuse" = 1;
    "net.ipv4.tcp_fin_timeout" = 15;
    "net.ipv4.tcp_keepalive_time" = 300;
    "net.ipv4.tcp_keepalive_probes" = 5;
    "net.ipv4.tcp_keepalive_intvl" = 15;
    "net.ipv4.tcp_mtu_probing" = 1;

    # Memory Management (K8s Requirement & High-Load Optimization)
    "vm.swappiness" = 0;
    "vm.overcommit_memory" = 1;
    "vm.panic_on_oom" = 0;
    "vm.dirty_ratio" = 40;
    "vm.dirty_background_ratio" = 10;
    "vm.min_free_kbytes" = 131072;
    "vm.max_map_count" = 1048576;

    # File System & Process Limits
    "fs.file-max" = 2097152;
    "fs.inotify.max_user_watches" = 524288;
    "fs.inotify.max_user_instances" = 8192;
    "kernel.pid_max" = 4194304;

    # ARP & Conntrack Optimization
    "net.ipv4.neigh.default.gc_thresh1" = 4096;
    "net.ipv4.neigh.default.gc_thresh2" = 8192;
    "net.ipv4.neigh.default.gc_thresh3" = 16384;
    "net.netfilter.nf_conntrack_max" = 1048576;

    # Security Hardening (CIS Benchmark)
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
  };

  # Disable swap (K8s requirement)
  swapDevices = [];

  # Persistent eBPF filesystem mount (Cilium/K8s eBPF support)
  fileSystems."/sys/fs/bpf" = {
    device = "bpffs";
    fsType = "bpf";
  };

  # Networking
  networking.hostName = "kube-ready-nixos";
  networking.useDHCP = true;
  networking.firewall.enable = false; # K8s CNI manages iptables/nftables

  # Vagrant User & SSH Key Setup
  users.extraUsers.vagrant = {
    isNormalUser = true;
    home = "/home/vagrant";
    extraGroups = [ "wheel" "docker" "containerd" ];
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN1YdxBpNlzxDqfJyw/QKow1F+wvG9hXGoqiysfJOn5Y vagrant insecure public key"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  # SSH Server Setup
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };

  # Container Runtime
  virtualisation.containerd.enable = true;
  virtualisation.docker.enable = true;

  # CSI & Storage Prerequisites (Longhorn / Open-iSCSI)
  services.openiscsi = {
    enable = true;
    name = "iqn.2026-08.org.nixos:vagrant";
  };

  # Security Resource Limits
  security.pam.loginLimits = [
    { domain = "*"; item = "nofile"; type = "soft"; value = "1048576"; }
    { domain = "*"; item = "nofile"; type = "hard"; value = "1048576"; }
    { domain = "*"; item = "nproc"; type = "soft"; value = "65535"; }
    { domain = "*"; item = "nproc"; type = "hard"; value = "65535"; }
    { domain = "*"; item = "memlock"; type = "soft"; value = "unlimited"; }
    { domain = "*"; item = "memlock"; type = "hard"; value = "unlimited"; }
  ];

  # Packages: K8s tools, Storage, Network utilities
  environment.systemPackages = with pkgs; [
    # K8s CLI & CRI tools
    kubectl
    kubernetes-helm
    cri-tools

    # Networking & Security
    iptables
    ipset
    ipvsadm
    ebtables
    socat
    conntrack-tools

    # Storage & CSI Prerequisites
    openiscsi
    cryptsetup
    lvm2

    # Utility Tools
    curl
    wget
    git
    jq
    htop
    nettools
    pciutils
    usbutils
  ];

  # Metadata & License Information (/etc/vagrant-box/)
  environment.etc."vagrant-box/info.txt".text = ''
    ===============================================
      dasomel/nixos-kube-ready Vagrant Box
    ===============================================

    Box Name:     dasomel/nixos-kube-ready
    Base OS:      NixOS (Declarative Linux)
    Version:      0.1.0
    Purpose:      Kubernetes-ready optimized immutable OS
    License:      MIT License

    Source:       https://github.com/dasomel/kube-ready-box
    Box URL:      https://app.vagrantup.com/dasomel/boxes/nixos-kube-ready

    ===============================================
      Pre-installed Optimizations & Pre-requisites
    ===============================================

    1. Kernel tuning & Sysctl optimization for K8s
    2. Swap disabled (K8s requirement)
    3. Network modules loaded (overlay, br_netfilter, iscsi_tcp)
    4. Persistent eBPF mount (/sys/fs/bpf)
    5. Container runtimes (containerd, docker) pre-installed
    6. K8s CLI tools (kubectl, helm, cri-tools) pre-installed
    7. Storage CSI pre-requisites (openiscsi, cryptsetup, lvm2)

    ===============================================
      License Information
    ===============================================

    This Vagrant Box is distributed under the MIT License.

    Copyright (c) 2026 dasomel <dasomell@gmail.com>

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
  '';

  environment.etc."vagrant-box/LICENSE".text = ''
    MIT License

    Copyright (c) 2026 dasomel <dasomell@gmail.com>

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
  '';

  environment.etc."vagrant-box/manifest.json".text = ''
    {
      "name": "dasomel/nixos-kube-ready",
      "version": "0.1.0",
      "base_os": "NixOS",
      "license": "MIT",
      "spdx_id": "MIT",
      "author": "dasomel <dasomell@gmail.com>",
      "source": "https://github.com/dasomel/kube-ready-box",
      "sbom": {
        "generator": "nix-closure-info",
        "format": "spdx-json"
      }
    }
  '';

  # Login MOTD Banner
  users.motd = ''

    ╔══════════════════════════════════════════════╗
    ║   dasomel/nixos-kube-ready v0.1.0            ║
    ║   NixOS + Kubernetes Optimizations           ║
    ╚══════════════════════════════════════════════╝

    📦 Box Info: cat /etc/vagrant-box/info.txt
    📜 License: cat /etc/vagrant-box/LICENSE
    📚 K8s Setup Guide: https://kubernetes.io/docs/setup/

  '';

  # System State Version
  system.stateVersion = "24.05";
}
