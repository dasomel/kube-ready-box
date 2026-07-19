source "virtualbox-iso" "ubuntu-vbox-amd64" {
  iso_url          = local.iso_url_amd64
  iso_checksum     = local.iso_checksum_amd64
  vm_name          = "ubuntu-${var.ubuntu_version}-virtualbox-amd64"
  guest_os_type    = "Ubuntu_64"
  cpus             = var.cpus
  memory           = var.memory
  disk_size        = var.disk_size
  headless         = var.headless
  ssh_username     = var.ssh_username
  ssh_password     = var.ssh_password
  ssh_timeout      = "1h"
  shutdown_command = "echo '${var.ssh_password}' | sudo -S shutdown -P now"
  http_directory   = "http/autoinstall-${var.filesystem}"

  boot_wait = "10s"
  boot_command = [
    "c<wait>",
    "linux /casper/vmlinuz autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---<enter>",
    "initrd /casper/initrd<enter>",
    "boot<enter>"
  ]

  vboxmanage = [
    ["modifyvm", "{{.Name}}", "--firmware", "efi"],
    ["modifyvm", "{{.Name}}", "--nat-localhostreachable1", "on"],
    ["modifyvm", "{{.Name}}", "--memory", "${var.memory}"],
    ["modifyvm", "{{.Name}}", "--cpus", "${var.cpus}"]
  ]
}

build {
  sources = ["source.virtualbox-iso.ubuntu-vbox-amd64"]

  # 스크립트 순차 실행
  provisioner "shell" {
    scripts = [
      "scripts/00-vagrant-setup.sh",
      "scripts/01-base.sh",
      "scripts/02-os-tuning.sh",
      "scripts/03-os-packages.sh",
      "scripts/04-k8s-prereq.sh",
      "scripts/05-disk-tuning.sh",
      "scripts/06-nic-tuning.sh",
      "scripts/ubuntu-tuning.sh",
      "scripts/07-check-tuning.sh",
      "scripts/08-security-check.sh",
      "scripts/license-info.sh",
      "scripts/generate-sbom.sh",
      "scripts/99-cleanup.sh"
    ]
    execute_command = "echo '${var.ssh_password}' | sudo -S sh -c '{{ .Vars }} {{ .Path }}'"
  }

  # Vagrant Box 생성
  post-processor "vagrant" {
    output              = "output-vagrant/ubuntu-${var.ubuntu_version}-${var.filesystem}-virtualbox-amd64.box"
    compression_level   = 9
    keep_input_artifact = false
  }
}
