packer {
  required_version = ">= 1.10.0"

  # 버전을 ">= 1.0.0" 처럼 열어두면 packer init 실행마다 그 시점의 최신 버전을
  # 조용히 새로 받아온다 (#30 공급망 고정 — floating 버전 제약도 동일한 위험).
  # 검증하고 실제 사용 중인 정확한 버전으로 고정한다.
  required_plugins {
    virtualbox = {
      version = "= 1.1.3"
      source  = "github.com/hashicorp/virtualbox"
    }
    vmware = {
      version = "= 1.2.0"
      source  = "github.com/hashicorp/vmware"
    }
    vagrant = {
      version = "= 1.1.6"
      source  = "github.com/hashicorp/vagrant"
    }
  }
}

variable "ubuntu_version" {
  type    = string
  default = "24.04"

  validation {
    condition     = contains(["24.04", "26.04"], var.ubuntu_version)
    error_message = "Ubuntu version must be either '24.04' or '26.04'."
  }
}

variable "box_version" {
  type    = string
  default = "0.2.3"
}

variable "filesystem" {
  type        = string
  default     = "ext4"
  description = "Root filesystem type: ext4 or xfs"

  validation {
    condition     = contains(["ext4", "xfs"], var.filesystem)
    error_message = "Filesystem must be either 'ext4' or 'xfs'."
  }
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

variable "cpus" {
  type    = number
  default = 2
}

variable "memory" {
  type    = number
  default = 2048
}

variable "disk_size" {
  type    = number
  default = 1000000 # 1TB - thin provisioning, actual size depends on usage
}

variable "headless" {
  type    = bool
  default = true
}

locals {
  iso_data = {
    "24.04" = {
      amd64_url = "https://mirrors.edge.kernel.org/ubuntu-releases/24.04/ubuntu-24.04.3-live-server-amd64.iso"
      amd64_sum = "sha256:c3514bf0056180d09376462a7a1b4f213c1d6e8ea67fae5c25099c6fd3d8274b"
      arm64_url = "https://cdimage.ubuntu.com/releases/24.04/release/ubuntu-24.04.3-live-server-arm64.iso"
      arm64_sum = "sha256:2ee2163c9b901ff5926400e80759088ff3b879982a3956c02100495b489fd555"
    }
    "26.04" = {
      amd64_url = "https://releases.ubuntu.com/26.04/ubuntu-26.04-live-server-amd64.iso"
      amd64_sum = "sha256:dec49008a71f6098d0bcfc822021f4d042d5f2db279e4d75bdd981304f1ca5d9"
      arm64_url = "https://cdimage.ubuntu.com/releases/26.04/release/ubuntu-26.04-live-server-arm64.iso"
      arm64_sum = "sha256:c9aa567e6560b2eddae3af03fc686002e35b6fee96f97fd5df3271e846439fdd"
    }
  }
  iso_url_amd64      = local.iso_data[var.ubuntu_version].amd64_url
  iso_checksum_amd64 = local.iso_data[var.ubuntu_version].amd64_sum
  iso_url_arm64      = local.iso_data[var.ubuntu_version].arm64_url
  iso_checksum_arm64 = local.iso_data[var.ubuntu_version].arm64_sum
}

# gVisor 샌드박스 프로파일 (#11). 기본 0 = 표준 박스에 런타임을 넣지 않는다.
variable "sandbox_profile" {
  type    = string
  default = "0"
}

# 재현 가능한 빌드를 위해 gVisor 릴리스를 고정한다. "latest" 는 빌드마다 결과가 달라진다.
variable "gvisor_release" {
  type    = string
  default = "latest"
}
