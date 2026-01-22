# dasomel/ubuntu-24.04 Box 사용 가이드

> **참고**: 이 문서는 `dasomel/ubuntu-24.04` Box 사용법입니다.
> Box 빌드는 [claude.md](claude.md) 참조.

## 1. Vagrantfile 예시

### 단일 노드 사용

```ruby
Vagrant.configure("2") do |config|
  # 아키텍처 자동 감지
  host_arch = `uname -m`.strip

  # dasomel/ubuntu-24.04 Box는 아키텍처 자동 선택
  config.vm.box = "dasomel/ubuntu-24.04"

  if host_arch == "arm64" || host_arch == "aarch64"
    config.vm.provider "vmware_desktop" do |v|
      v.vmx["memsize"] = "4096"
      v.vmx["numvcpus"] = "2"
    end
  else
    config.vm.provider "virtualbox" do |vb|
      vb.memory = 4096
      vb.cpus = 2
    end
  end

  config.vm.hostname = "k8s-ready"
  config.vm.network "private_network", ip: "192.168.56.10"
end
```

### 멀티 노드 클러스터용

```ruby
Vagrant.configure("2") do |config|
  # Provider/아키텍처 설정
  PROVIDER = ENV['VAGRANT_PROVIDER'] || "virtualbox"
  host_arch = `uname -m`.strip
  ARCH = host_arch == "arm64" || host_arch == "aarch64" ? "arm64" : "amd64"

  # 노드 설정
  NODE_COUNT = 3
  NETWORK_PREFIX = "192.168.56"

  # dasomel/ubuntu-24.04는 아키텍처 자동 선택
  BOX_NAME = "dasomel/ubuntu-24.04"

  (1..NODE_COUNT).each do |i|
    config.vm.define "node-#{i}" do |node|
      node.vm.box = BOX_NAME
      node.vm.hostname = "k8s-node-#{i}"
      node.vm.network "private_network", ip: "#{NETWORK_PREFIX}.#{10 + i}"

      node.vm.provider PROVIDER do |v|
        if PROVIDER == "vmware_desktop"
          v.vmx["memsize"] = i == 1 ? "4096" : "2048"
          v.vmx["numvcpus"] = "2"
        else
          v.memory = i == 1 ? 4096 : 2048
          v.cpus = 2
        end
      end
    end
  end
end
```

---

## 2. 기본 사용법

### VM 시작/중지

```bash
# Box 시작
vagrant up

# 특정 노드만 시작
vagrant up node-1

# VM 중지
vagrant halt

# VM 삭제
vagrant destroy -f

# Box 업데이트 확인
vagrant box outdated
vagrant box update
```

### SSH 접속

```bash
# 기본 접속
vagrant ssh

# 특정 노드 접속
vagrant ssh node-1

# 명령어 직접 실행
vagrant ssh -c "cat /etc/vagrant-box/info.json"
```

---

## 3. K8s 클러스터 구성

> K8s 설치 후 상세 설정은 [k8s-post-install.md](k8s-post-install.md) 참조

### Master 노드 설정 (node-1)

```bash
# node-1 (master)에서 실행
vagrant ssh node-1

# 1. containerd 설치
sudo apt-get update && sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd && sudo systemctl enable containerd

# 2. K8s 설치 (원하는 버전)
K8S_VERSION="v1.31"
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key" | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update && sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# 3. Master 초기화
sudo kubeadm init --apiserver-advertise-address=192.168.56.11 --pod-network-cidr=10.244.0.0/16

# 4. kubeconfig 설정
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# 5. CNI 설치
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

### Worker 노드 조인

```bash
# Master에서 조인 명령어 생성
kubeadm token create --print-join-command

# Worker 노드 (node-2, node-3)에서 실행
vagrant ssh node-2
# (Master에서 출력된 kubeadm join 명령어 실행)
```

### 클러스터 확인

```bash
# Master에서 실행
kubectl get nodes
kubectl get pods -A
```

---

## 4. Provider별 설정

### VirtualBox

```ruby
config.vm.provider "virtualbox" do |vb|
  vb.memory = 4096
  vb.cpus = 2
  vb.name = "k8s-node"

  # 네트워크 성능 향상
  vb.customize ["modifyvm", :id, "--nictype1", "virtio"]

  # Nested virtualization (선택)
  vb.customize ["modifyvm", :id, "--nested-hw-virt", "on"]
end
```

### VMware Fusion

```ruby
config.vm.provider "vmware_desktop" do |v|
  v.vmx["memsize"] = "4096"
  v.vmx["numvcpus"] = "2"
  v.vmx["displayName"] = "k8s-node"

  # Nested virtualization
  v.vmx["vhv.enable"] = "TRUE"
end
```

---

## 5. 네트워크 설정

### Private Network (Host-Only)

```ruby
# 고정 IP
config.vm.network "private_network", ip: "192.168.56.10"

# DHCP
config.vm.network "private_network", type: "dhcp"
```

### Port Forwarding

```ruby
# K8s API Server
config.vm.network "forwarded_port", guest: 6443, host: 6443

# NodePort 범위
(30000..30010).each do |port|
  config.vm.network "forwarded_port", guest: port, host: port
end
```

### Public Network (Bridged)

```ruby
config.vm.network "public_network", bridge: "en0: Wi-Fi"
```

---

## 6. 문제 해결

### Box 다운로드 실패

```bash
# 캐시 정리
vagrant box remove dasomel/ubuntu-24.04 --all
rm -rf ~/.vagrant.d/boxes/dasomel-VAGRANTSLASH-ubuntu-24.04

# 재다운로드
vagrant box add dasomel/ubuntu-24.04
```

### VM 시작 실패

```bash
# 로그 확인
vagrant up --debug

# VirtualBox 로그
cat ~/VirtualBox\ VMs/<vm-name>/Logs/VBox.log
```

### 네트워크 연결 안됨

```bash
# VM 내부에서 확인
ip addr
ping 192.168.56.1  # Host

# Host에서 확인
ping 192.168.56.10  # VM
```

---

## 참고 자료

- [Vagrant 공식 문서](https://developer.hashicorp.com/vagrant/docs)
- [VirtualBox 네트워크 설정](https://www.virtualbox.org/manual/ch06.html)
- [VMware Fusion Provider](https://developer.hashicorp.com/vagrant/docs/providers/vmware)
