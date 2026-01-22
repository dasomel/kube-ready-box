source "virtualbox-iso" "ubuntu-vbox-arm64" {
  # Disable export to OVF since this capability is not supported for MacOS 
  # Silicon chips. We will manually create the OVF and VMDK files as part of
  # the post-processor.
  skip_export = true

  # ISO settings
  iso_url       = var.iso_url_arm64
  iso_checksum  = var.iso_checksum_arm64
  iso_interface = "virtio"

  # VM settings
  vm_name              = "ubuntu-24.04-virtualbox-arm64"
  guest_os_type        = "Ubuntu_arm64"
  cpus                 = var.cpus
  memory               = var.memory
  disk_size            = var.disk_size
  hard_drive_interface = "virtio"
  headless             = var.headless

  # SSH settings
  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = "1h"

  # HTTP server for autoinstall (kept for compatibility, though we use cd_files)
  http_directory = "http/autoinstall"

  # CD files for autoinstall - more reliable on ARM64 than boot_command typing
  cd_files = [
    "http/autoinstall/user-data",
    "http/autoinstall/meta-data"
  ]
  cd_label = "cidata"

  # Boot settings - increased wait time for ARM64 EFI boot
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
    # Basic hardware first
    ["modifyvm", "{{.Name}}", "--vram", "16"],
    ["modifyvm", "{{.Name}}", "--graphicscontroller", "VMSVGA"],

    # Firmware BEFORE storage
    ["modifyvm", "{{.Name}}", "--firmware", "efi"],

    # Input devices - PS2 for boot_command compatibility on ARM64
    ["modifyvm", "{{.Name}}", "--mouse", "ps2"],
    ["modifyvm", "{{.Name}}", "--keyboard", "ps2"],

    # Boot order
    ["modifyvm", "{{.Name}}", "--boot1", "disk"],
    ["modifyvm", "{{.Name}}", "--boot2", "dvd"],
    ["modifyvm", "{{.Name}}", "--boot3", "floppy"],
    ["modifyvm", "{{.Name}}", "--boot4", "none"],

    # Network
    ["modifyvm", "{{.Name}}", "--macaddress1", "080027F0F51D"],
    ["modifyvm", "{{.Name}}", "--nat-localhostreachable1", "on"],

    # Audio
    ["modifyvm", "{{.Name}}", "--audio-driver", "coreaudio"],
    ["modifyvm", "{{.Name}}", "--audio-controller", "hda"],
    ["modifyvm", "{{.Name}}", "--audioin", "off"],
    ["modifyvm", "{{.Name}}", "--audioout", "on"],

    # Other settings
    ["modifyvm", "{{.Name}}", "--rtcuseutc", "on"],
    ["modifyvm", "{{.Name}}", "--usbxhci", "on"],
    ["modifyvm", "{{.Name}}", "--clipboard-mode", "disabled"]
  ]
}

build {
  sources = ["source.virtualbox-iso.ubuntu-vbox-arm64"]

  # Provisioning scripts
  provisioner "shell" {
    scripts = [
      "scripts/00-vagrant-setup.sh",
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

  # Manually create OVF and VMDK files to create Vagrant box
  # This is required because VirtualBox on macOS Silicon cannot export to OVF
  provisioner "shell-local" {
    environment_vars = [
      "VM_NAME=ubuntu-24.04-virtualbox-arm64",
      "MEMORY=${var.memory}",
      "DISK_SIZE=${var.disk_size}",
      "VDI_SOURCE=${path.root}/output-ubuntu-vbox-arm64/ubuntu-24.04-virtualbox-arm64.vdi",
      "OUTPUT_DIR=${path.root}/output-vagrant",
      "TEMPLATE_PATH=${path.root}/templates/ovf.tpl",
      "METADATA_PATH=${path.root}/templates/metadata.tpl",
      "VAGRANTFILE_PATH=${path.root}/templates/vagrantfile.tpl",
    ]

    inline = [
      # Get absolute paths (path.root may be relative)
      "SCRIPT_DIR=$(cd \"$(dirname \"$0\")\" && pwd)",
      "PACKER_DIR=$(pwd)",
      "TEMPLATE_PATH=\"$PACKER_DIR/templates/ovf.tpl\"",
      "METADATA_PATH=\"$PACKER_DIR/templates/metadata.tpl\"",
      "VAGRANTFILE_PATH=\"$PACKER_DIR/templates/vagrantfile.tpl\"",
      "OUTPUT_DIR=\"$PACKER_DIR/output-vagrant\"",
      "VDI_SOURCE=\"$PACKER_DIR/output-ubuntu-vbox-arm64/ubuntu-24.04-virtualbox-arm64.vdi\"",

      # Initial cleanup of any existing output directory and disks
      "echo 'Cleaning up previous files...'",
      "rm -rf \"$OUTPUT_DIR\"",
      "VBoxManage list hdds | grep Location | grep \"$VM_NAME-disk001.vmdk\" | cut -d: -f2 | xargs -I {} VBoxManage closemedium disk \"{}\" --delete || true",
      "sleep 2",

      # Create fresh output directory
      "echo \"OUTPUT_DIR is set to: $OUTPUT_DIR\"",
      "mkdir -p \"$OUTPUT_DIR\"",

      # Stop VM so we can interact with VDI
      "echo 'Ensuring VM is stopped...'",
      "VBoxManage list runningvms | grep -q \"$VM_NAME\" && VBoxManage controlvm \"$VM_NAME\" poweroff || true",
      "sleep 2",

      # Convert VDI to VMDK
      "echo 'Converting VDI to VMDK...'",
      "VBoxManage clonemedium \"$VDI_SOURCE\" \"$OUTPUT_DIR/$VM_NAME-disk001.vmdk\" --format VMDK --variant StreamOptimized",

      # Verify VMDK creation
      "if [ ! -f \"$OUTPUT_DIR/$VM_NAME-disk001.vmdk\" ]; then echo 'Error: VMDK file was not created!' && exit 1; fi",

      # Get UUIDs - extract from VMDK file directly and generate fresh VM UUID
      "echo 'Getting disk UUID from VMDK file...'",
      "disk_uuid=$(grep -a 'ddb.uuid.image' \"$OUTPUT_DIR/$VM_NAME-disk001.vmdk\" | head -1 | sed 's/.*\"\\(.*\\)\".*/\\1/' | tr ' ' '-')",
      "if [ -z \"$disk_uuid\" ]; then disk_uuid=$(uuidgen | tr '[:upper:]' '[:lower:]'); fi",
      "vm_uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')",
      "echo \"Disk UUID: $disk_uuid\"",
      "echo \"VM UUID: $vm_uuid\"",

      # Calculate disk size in bytes for OVF 2.0 format
      "DISK_SIZE_BYTES=$((DISK_SIZE * 1024 * 1024))",
      "echo \"Disk size bytes: $DISK_SIZE_BYTES\"",

      # Export required variables for template
      "export disk_uuid",
      "export vm_uuid",
      "export DISK_SIZE_BYTES",

      # Process templates and generate files
      "echo 'Processing templates...'",
      "cd \"$OUTPUT_DIR\" || exit 1",
      "envsubst < \"$TEMPLATE_PATH\" > \"box.ovf\"",
      "envsubst < \"$METADATA_PATH\" > \"metadata.json\"",
      "envsubst < \"$VAGRANTFILE_PATH\" > \"Vagrantfile\"",

      # Create box file
      "echo 'Creating box file...'",
      "tar -czf \"$VM_NAME.box\" ./metadata.json ./Vagrantfile ./box.ovf ./$VM_NAME-disk001.vmdk",

      # Verify box file
      "if [ ! -f \"$VM_NAME.box\" ]; then echo 'Error: Box file was not created!' && exit 1; fi",
      "echo '✅ Box file created successfully:'",
      "ls -lh \"$VM_NAME.box\"",

      # Final cleanup
      "echo 'Performing final cleanup...'",
      "cd .. || exit 1",
      "VBoxManage closemedium disk \"$OUTPUT_DIR/$VM_NAME-disk001.vmdk\" --delete || true",

      # Unregister and delete the VM
      "echo 'Unregistering VM...'",
      "VBoxManage unregistervm \"$VM_NAME\" --delete || true",
    ]
  }
}
