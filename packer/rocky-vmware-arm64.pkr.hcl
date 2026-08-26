source "vmware-iso" "rocky-vmware-arm64" {
  iso_url              = local.rocky_iso_url_arm64
  iso_checksum         = local.rocky_iso_checksum_arm64
  vm_name              = "rocky-${var.rocky_version}-vmware-arm64"
  guest_os_type        = "arm-rhel9-64"
  network_adapter_type = "vmxnet3"
  cpus                 = var.cpus
  memory               = 4096
  disk_size            = var.disk_size
  disk_adapter_type    = "nvme"
  cdrom_adapter_type   = "sata"
  headless             = false
  ssh_username         = var.ssh_username
  ssh_password         = var.ssh_password
  ssh_timeout          = "2h"
  shutdown_command     = "echo '${var.ssh_password}' | sudo -S shutdown -P now"
  http_directory       = local.rocky_http_dir

  boot_wait = "10s"
  boot_command = [
    "<up><wait>e<wait>",
    "<down><down><end><wait>",
    " inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg<wait>",
    "<f10>"
  ]

  vmx_data = {
    "ethernet0.virtualdev"      = "vmxnet3"
    "usb_xhci.present"          = "TRUE"
    "firmware"                  = "efi"
    "sata0:0.present"           = "TRUE"
    "sata0:0.deviceType"        = "cdrom-image"
    "RemoteDisplay.vnc.enabled" = "TRUE"
    "RemoteDisplay.vnc.port"    = "5900"
  }

  vnc_port_min = 5900
  vnc_port_max = 5999
}

build {
  sources = ["source.vmware-iso.rocky-vmware-arm64"]

  provisioner "shell" {
    scripts = [
      "scripts/00-egress-restrict.sh",
      "scripts/00-vagrant-setup.sh",
      "scripts/01-base-rocky.sh",
      "scripts/02-os-tuning.sh",
      "scripts/03-os-packages-rocky.sh",
      "scripts/04-k8s-prereq-rocky.sh",
      "scripts/05-disk-tuning-rocky.sh",
      "scripts/06-nic-tuning.sh",
      "scripts/rocky-tuning.sh",
      "scripts/08-security-check-rocky.sh",
      "scripts/license-info.sh",
      "scripts/generate-sbom.sh",
      "scripts/10-sandbox-runtime.sh",
      "scripts/98-first-boot-identity.sh",
      "scripts/99-cleanup.sh"
    ]
    environment_vars = [
      "RESTRICT_BUILD_EGRESS=${var.restrict_build_egress}",
      "KUBE_READY_COMMIT_SHA=${var.commit_sha}",
      "KUBE_READY_BUILD_ID=${var.build_id}",
      "KUBE_READY_WORKFLOW_RUN=${var.workflow_run}",
      "KUBE_READY_BOX_VERSION=${var.box_version}",
      "SANDBOX_PROFILE=${var.sandbox_profile}",
      "GVISOR_RELEASE=${var.gvisor_release}"
    ]
    execute_command = "echo '${var.ssh_password}' | sudo -S sh -c '{{ .Vars }} {{ .Path }}'"
  }

  post-processor "vagrant" {
    output              = "output-vagrant/rocky-${var.rocky_version}-${var.filesystem}-vmware-arm64.box"
    compression_level   = 9
    keep_input_artifact = false
  }
}
