variable "source_vmx" {
  type        = string
  description = "Path to source VMX file"
  default     = ""
}

source "vmware-vmx" "ubuntu-vmx" {
  source_path      = var.source_vmx
  ssh_username     = var.ssh_username
  ssh_password     = var.ssh_password
  ssh_timeout      = "20m"
  shutdown_command = "echo 'vagrant' | sudo -S shutdown -P now"
  output_directory = "output-vmware-vmx"
  vm_name          = "ubuntu-24.04-arm64"
  headless         = false
}

build {
  sources = ["source.vmware-vmx.ubuntu-vmx"]

  # Install vagrant insecure public key
  provisioner "shell" {
    inline = [
      "mkdir -p ~/.ssh",
      "chmod 700 ~/.ssh",
      "curl -fsSL https://raw.githubusercontent.com/hashicorp/vagrant/main/keys/vagrant.pub >> ~/.ssh/authorized_keys",
      "chmod 600 ~/.ssh/authorized_keys"
    ]
  }

  # Basic setup for vagrant box
  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y open-vm-tools",
      "sudo systemctl enable ssh"
    ]
  }

  # Clean up
  provisioner "shell" {
    inline = [
      "sudo apt-get clean",
      "sudo rm -rf /var/lib/apt/lists/*",
      "sudo rm -rf /tmp/*",
      "sudo truncate -s 0 /etc/machine-id",
      "history -c"
    ]
  }

  post-processor "vagrant" {
    output               = "ubuntu-24.04-vmware-arm64.box"
    vagrantfile_template = "templates/vagrantfile-vmware.tpl"
  }
}
