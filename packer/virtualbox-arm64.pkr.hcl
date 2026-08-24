source "virtualbox-iso" "ubuntu-vbox-arm64" {
  skip_export          = true
  iso_url              = local.iso_url_arm64
  iso_checksum         = local.iso_checksum_arm64
  iso_interface        = "virtio"
  vm_name              = "ubuntu-${var.ubuntu_version}-virtualbox-arm64"
  guest_os_type        = "Ubuntu_arm64"
  cpus                 = var.cpus
  memory               = var.memory
  disk_size            = var.disk_size
  hard_drive_interface = "virtio"
  headless             = var.headless
  ssh_username         = var.ssh_username
  ssh_password         = var.ssh_password
  ssh_timeout          = "1h"
  http_directory       = "http/autoinstall-${var.filesystem}"
  cd_files = [
    "http/autoinstall-${var.filesystem}/user-data",
    "http/autoinstall-${var.filesystem}/meta-data"
  ]
  cd_label  = "cidata"
  boot_wait = "10s"
  boot_command = [
    "c<wait>",
    "linux /casper/vmlinuz autoinstall ds=nocloud;s=/cdrom/ ---<enter><wait>",
    "initrd /casper/initrd<enter><wait>",
    "boot<enter>"
  ]
  shutdown_command = "echo '${var.ssh_password}' | sudo -S shutdown -P now"
  disable_shutdown = true
  vboxmanage = [
    ["modifyvm", "{{.Name}}", "--vram", "16"],
    ["modifyvm", "{{.Name}}", "--graphicscontroller", "VMSVGA"],
    ["modifyvm", "{{.Name}}", "--firmware", "efi"],
    ["modifyvm", "{{.Name}}", "--mouse", "ps2"],
    ["modifyvm", "{{.Name}}", "--keyboard", "ps2"],
    ["modifyvm", "{{.Name}}", "--boot1", "disk"],
    ["modifyvm", "{{.Name}}", "--boot2", "dvd"],
    ["modifyvm", "{{.Name}}", "--boot3", "floppy"],
    ["modifyvm", "{{.Name}}", "--boot4", "none"],
    ["modifyvm", "{{.Name}}", "--macaddress1", "080027F0F51D"],
    ["modifyvm", "{{.Name}}", "--nat-localhostreachable1", "on"],
    ["modifyvm", "{{.Name}}", "--audio-driver", "coreaudio"],
    ["modifyvm", "{{.Name}}", "--audio-controller", "hda"],
    ["modifyvm", "{{.Name}}", "--audioin", "off"],
    ["modifyvm", "{{.Name}}", "--audioout", "on"],
    ["modifyvm", "{{.Name}}", "--rtcuseutc", "on"],
    ["modifyvm", "{{.Name}}", "--usbxhci", "on"],
    ["modifyvm", "{{.Name}}", "--clipboard-mode", "disabled"]
  ]
}

build {
  sources = ["source.virtualbox-iso.ubuntu-vbox-arm64"]
  provisioner "shell" {
    scripts = [
      "scripts/00-egress-restrict.sh",
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
  provisioner "shell-local" {
    environment_vars = [
      "VM_NAME=ubuntu-${var.ubuntu_version}-virtualbox-arm64",
      "BOX_NAME=ubuntu-${var.ubuntu_version}-${var.filesystem}-virtualbox-arm64",
      "MEMORY=${var.memory}",
      "DISK_SIZE=${var.disk_size}",
      "VDI_SOURCE=${path.root}/output-ubuntu-vbox-arm64/ubuntu-${var.ubuntu_version}-virtualbox-arm64.vdi",
      "OUTPUT_DIR=${path.root}/output-vagrant",
      "TEMPLATE_PATH=${path.root}/templates/ovf.tpl",
      "METADATA_PATH=${path.root}/templates/metadata.tpl",
      "VAGRANTFILE_PATH=${path.root}/templates/vagrantfile.tpl",
    ]
    inline = [
      "SCRIPT_DIR=$(cd \"$(dirname \"$0\")\" && pwd)",
      "PACKER_DIR=$(pwd)",
      "TEMPLATE_PATH=\"$PACKER_DIR/templates/ovf.tpl\"",
      "METADATA_PATH=\"$PACKER_DIR/templates/metadata.tpl\"",
      "VAGRANTFILE_PATH=\"$PACKER_DIR/templates/vagrantfile.tpl\"",
      "OUTPUT_DIR=\"$PACKER_DIR/output-vagrant\"",
      "VDI_SOURCE=\"$PACKER_DIR/output-ubuntu-vbox-arm64/ubuntu-${var.ubuntu_version}-virtualbox-arm64.vdi\"",
      "echo 'Cleaning up previous files...'",
      "rm -rf \"$OUTPUT_DIR\"",
      "VBoxManage list hdds | grep Location | grep \"$VM_NAME-disk001.vmdk\" | cut -d: -f2 | xargs -I {} VBoxManage closemedium disk \"{}\" --delete || true",
      "sleep 2",
      "mkdir -p \"$OUTPUT_DIR\"",
      "VBoxManage list runningvms | grep -q \"$VM_NAME\" && VBoxManage controlvm \"$VM_NAME\" poweroff || true",
      "sleep 2",
      "VBoxManage clonemedium \"$VDI_SOURCE\" \"$OUTPUT_DIR/$VM_NAME-disk001.vmdk\" --format VMDK --variant StreamOptimized",
      "if [ ! -f \"$OUTPUT_DIR/$VM_NAME-disk001.vmdk\" ]; then echo 'Error: VMDK file was not created!' && exit 1; fi",
      "disk_uuid=$(grep -a 'ddb.uuid.image' \"$OUTPUT_DIR/$VM_NAME-disk001.vmdk\" | head -1 | sed 's/.*\"\\(.*\\)\".*/\\1/' | tr ' ' '-')",
      "if [ -z \"$disk_uuid\" ]; then disk_uuid=$(uuidgen | tr '[:upper:]' '[:lower:]'); fi",
      "vm_uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')",
      "DISK_SIZE_BYTES=$((DISK_SIZE * 1024 * 1024))",
      "export disk_uuid vm_uuid DISK_SIZE_BYTES",
      "cd \"$OUTPUT_DIR\" || exit 1",
      "envsubst < \"$TEMPLATE_PATH\" > \"box.ovf\"",
      "envsubst < \"$METADATA_PATH\" > \"metadata.json\"",
      "envsubst < \"$VAGRANTFILE_PATH\" > \"Vagrantfile\"",
      "tar -czf \"$BOX_NAME.box\" ./metadata.json ./Vagrantfile ./box.ovf ./$VM_NAME-disk001.vmdk",
      "if [ ! -f \"$BOX_NAME.box\" ]; then echo 'Error: Box file was not created!' && exit 1; fi",
      "ls -lh \"$BOX_NAME.box\"",
      "cd .. || exit 1",
      "VBoxManage closemedium disk \"$OUTPUT_DIR/$VM_NAME-disk001.vmdk\" --delete || true",
      "VBoxManage unregistervm \"$VM_NAME\" --delete || true",
    ]
  }
}
