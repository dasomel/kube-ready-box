packer {
  required_version = ">= 1.8.0"

  required_plugins {
    virtualbox = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/virtualbox"
    }
    vmware = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/vmware"
    }
    vagrant = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/vagrant"
    }
  }
}

variable "ubuntu_version" {
  type    = string
  default = "24.04"
}

variable "box_version" {
  type    = string
  default = "0.1.0"
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
  default = 20000
}

variable "headless" {
  type    = bool
  default = true
}

variable "iso_url_amd64" {
  type    = string
  default = "https://releases.ubuntu.com/24.04/ubuntu-24.04.3-live-server-amd64.iso"
}

variable "iso_url_arm64" {
  type    = string
  default = "https://cdimage.ubuntu.com/releases/24.04/release/ubuntu-24.04.3-live-server-arm64.iso"
}

variable "iso_checksum_amd64" {
  type    = string
  default = "sha256:c3514bf0056180d09376462a7a1b4f213c1d6e8ea67fae5c25099c6fd3d8274b"
}

variable "iso_checksum_arm64" {
  type    = string
  default = "sha256:2ee2163c9b901ff5926400e80759088ff3b879982a3956c02100495b489fd555"
}
