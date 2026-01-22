#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 dasomel
set -e

echo "=== 02-os-tuning.sh: OS Kernel & Resource Tuning ==="

#=========================================
# 1. 커널 파라미터 최적화
#=========================================
echo "Configuring kernel parameters..."
cat <<EOF > /etc/sysctl.d/99-k8s-tuning.conf
#-----------------------------------------
# 네트워크 성능 최적화
#-----------------------------------------
# 소켓 연결 대기열 (기본 4096 → 65535)
# 컨테이너 환경에서 수백 개 프로세스가 동시 실행되므로 증가 필요
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535

# TCP 버퍼 크기 (16MB) - 고대역폭 워크로드용
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 262144
net.core.wmem_default = 262144

# TCP 메모리 설정 (min, default, max)
net.ipv4.tcp_rmem = 4096 262144 16777216
net.ipv4.tcp_wmem = 4096 262144 16777216

# TCP 연결 관리
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15

# TCP Keepalive (K8s 1.29+ safe sysctl)
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15

# MTU 탐색 활성화
net.ipv4.tcp_mtu_probing = 1

#-----------------------------------------
# 메모리 관리
#-----------------------------------------
# 스왑 사용 안함 (K8s 필수)
vm.swappiness = 0

# 메모리 오버커밋 허용 (fork 시 필요)
vm.overcommit_memory = 1

# OOM 발생 시 패닉 방지
vm.panic_on_oom = 0

# Dirty 페이지 관리 (I/O 집약적 워크로드)
vm.dirty_ratio = 40
vm.dirty_background_ratio = 10

# 최소 여유 메모리 (커널 할당용)
vm.min_free_kbytes = 131072

#-----------------------------------------
# 파일 시스템
#-----------------------------------------
# 파일 디스크립터 최대값
fs.file-max = 2097152

# inotify 제한 (컨테이너 환경 필수)
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 8192

# 최대 프로세스/네임스페이스 수
kernel.pid_max = 4194304

#-----------------------------------------
# ARP 캐시 최적화 (대규모 클러스터)
#-----------------------------------------
net.ipv4.neigh.default.gc_thresh1 = 4096
net.ipv4.neigh.default.gc_thresh2 = 8192
net.ipv4.neigh.default.gc_thresh3 = 16384

#-----------------------------------------
# conntrack 최적화 (서비스/Pod 많을 때)
#-----------------------------------------
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_tcp_timeout_established = 86400
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 3600

#-----------------------------------------
# 네트워크 보안 강화 (CIS Benchmark)
#-----------------------------------------
# IP Spoofing 방지 (Reverse Path Filtering)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# ICMP Redirect 수신 차단 (MITM 공격 방지)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0

# ICMP Redirect 전송 차단
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Source Routing 차단
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# SYN Flood 공격 방지
net.ipv4.tcp_syncookies = 1

# ICMP Broadcast 무시 (Smurf 공격 방지)
net.ipv4.icmp_echo_ignore_broadcasts = 1

# 잘못된 ICMP 응답 무시
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Martian 패킷 로깅 (보안 감사)
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
EOF

echo "Applying sysctl settings..."
sysctl --system

#=========================================
# 2. 리소스 제한 설정
#=========================================
echo "Configuring resource limits..."
cat <<EOF > /etc/security/limits.d/k8s.conf
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 65535
* hard nproc 65535
* soft memlock unlimited
* hard memlock unlimited
EOF

echo "=== 02-os-tuning.sh: Complete ==="
