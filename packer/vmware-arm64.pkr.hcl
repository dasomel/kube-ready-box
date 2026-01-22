source "vmware-iso" "ubuntu-vmware-arm64" {
  iso_url          = var.iso_url_arm64
  iso_checksum     = var.iso_checksum_arm64
  vm_name          = "ubuntu-24.04-vmware-arm64"
  guest_os_type      = "arm-ubuntu-64"
  cpus               = var.cpus
  memory             = 4096
  disk_size          = var.disk_size
  disk_adapter_type  = "nvme"
  cdrom_adapter_type = "sata"
  headless           = false
  ssh_username       = var.ssh_username
  ssh_password       = var.ssh_password
  ssh_timeout        = "30m"
  shutdown_command   = "echo '${var.ssh_password}' | sudo -S shutdown -P now"
  http_directory     = "http/autoinstall"

  boot_wait = "20s"
  boot_command = [
    "e<wait>",
    "<down><down><down><end>",
    " autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---",
    "<f10>"
  ]

  vmx_data = {
    "ethernet0.virtualdev"       = "vmxnet3"
    "usb_xhci.present"           = "TRUE"
    "firmware"                   = "efi"
    "sata0:0.present"            = "TRUE"
    "sata0:0.deviceType"         = "cdrom-image"
    "RemoteDisplay.vnc.enabled"  = "TRUE"
    "RemoteDisplay.vnc.port"     = "5900"
  }

  vnc_port_min = 5900
  vnc_port_max = 5999
}

build {
  sources = ["source.vmware-iso.ubuntu-vmware-arm64"]

  # 스크립트 순차 실행
  provisioner "shell" {
    scripts = [
      "scripts/01-base.sh",
      "scripts/02-os-tuning.sh",
      "scripts/03-os-packages.sh",
      "scripts/04-k8s-prereq.sh",
      "scripts/05-disk-tuning.sh",
      "scripts/06-nic-tuning.sh",
      "scripts/ubuntu2404-tuning.sh",
      "scripts/07-check-tuning.sh",
      "scripts/license-info.sh",
      "scripts/generate-sbom.sh",
      "scripts/99-cleanup.sh"
    ]
    execute_command = "echo '${var.ssh_password}' | sudo -S sh -c '{{ .Vars }} {{ .Path }}'"
  }

  # Vagrant Box 생성
  post-processor "vagrant" {
    output               = "output-vagrant/ubuntu-24.04-vmware-arm64.box"
    compression_level    = 9
    keep_input_artifact  = false
  }
}
