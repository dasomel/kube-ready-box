source "vmware-iso" "ubuntu-vmware-amd64" {
  iso_url              = local.iso_url_amd64
  iso_checksum         = local.iso_checksum_amd64
  vm_name              = "ubuntu-${var.ubuntu_version}-vmware-amd64"
  guest_os_type        = "ubuntu-64"
  network_adapter_type = "vmxnet3"
  cpus                 = var.cpus
  memory               = var.memory
  disk_size            = var.disk_size
  headless             = var.headless
  ssh_username         = var.ssh_username
  ssh_password         = var.ssh_password
  ssh_timeout          = "1h"
  shutdown_command     = "echo '${var.ssh_password}' | sudo -S shutdown -P now"
  http_directory       = "http/autoinstall-${var.filesystem}"

  boot_wait = "10s"
  boot_command = [
    "c<wait>",
    "linux /casper/vmlinuz autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---<enter>",
    "initrd /casper/initrd<enter>",
    "boot<enter>"
  ]

  vmx_data = {
    "ethernet0.virtualdev" = "vmxnet3"
    "firmware"             = "efi"
  }
}

build {
  sources = ["source.vmware-iso.ubuntu-vmware-amd64"]

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
      "scripts/09-k8s-node-preflight.sh",
      "scripts/10-sandbox-runtime.sh",
      "scripts/99-cleanup.sh"
    ]
    environment_vars = [
      "SANDBOX_PROFILE=${var.sandbox_profile}",
      "GVISOR_RELEASE=${var.gvisor_release}"
    ]
    execute_command = "echo '${var.ssh_password}' | sudo -S sh -c '{{ .Vars }} {{ .Path }}'"
  }

  post-processor "vagrant" {
    output              = "output-vagrant/ubuntu-${var.ubuntu_version}-${var.filesystem}-vmware-amd64.box"
    compression_level   = 9
    keep_input_artifact = false
  }
}
