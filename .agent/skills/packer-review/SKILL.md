---
name: packer-review
description: Review Packer templates (.pkr.hcl files) for security vulnerabilities, best practices, multi-architecture compatibility, and Ubuntu Cloud Image optimization when reviewing or modifying Packer configurations
---

# Packer Template Review

Comprehensive review of Packer templates for building Vagrant boxes with focus on security, best practices, and multi-architecture support.

## Instructions

When reviewing Packer templates (.pkr.hcl files), systematically check the following:

### 1. Security Checks (CRITICAL)

- **No hardcoded secrets**: Check for passwords, API tokens, or SSH keys in template
  - Bad: `ssh_password = "vagrant123"`
  - Good: `ssh_password = var.ssh_password`
- **Secure SSH configuration**:
  - Default vagrant user with known password is acceptable for dev boxes
  - Ensure `ssh_timeout` is set (default: "20m")
- **File permissions**: Scripts should use `execute_command` with proper sudo
  - Example: `execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"`
- **ISO checksums**: Always verify with SHA256 checksums
  - Use `iso_checksum = "file:https://..."` format
- **Boot command security**: No credentials in boot_command if possible

### 2. Best Practices

#### Build Configuration
- **Headless mode**: Enable for CI/CD (`headless = true`)
- **Resource allocation**: Appropriate CPU/memory for build target
  - Minimum: 2 CPU, 2GB RAM
  - Recommended: 4 CPU, 4GB RAM for faster builds
- **Disk size**: Match target use case (20GB+ for K8s nodes)
- **Timeouts**: Set appropriate `boot_wait`, `ssh_timeout`

#### Provisioners
- **Script ordering**: Number scripts (01-base.sh, 02-tuning.sh) for clarity
- **Error handling**: Use `set -e` in shell scripts
- **Idempotency**: Scripts should be rerunnable
- **Progressive execution**: Break complex provisioning into multiple scripts

#### Post-Processors
- **Vagrant box output**: Use `vagrant` post-processor
- **Compression**: Set `compression_level = 9` for release builds
- **Keep artifacts**: `keep_input_artifact = false` for disk space
- **Output naming**: Use descriptive names with provider/arch

### 3. Multi-Architecture Compatibility

#### VirtualBox
- **AMD64**: `guest_os_type = "Ubuntu_64"`
- **ARM64**: `guest_os_type = "Ubuntu_arm64"` (VirtualBox 7.1+)
- **ISO URLs**: Match architecture
  - AMD64: `ubuntu-24.04-server-cloudimg-amd64.img`
  - ARM64: `ubuntu-24.04-server-cloudimg-arm64.img`

#### VMware Fusion
- **AMD64**: `guest_os_type = "ubuntu-64"`
- **ARM64**: `guest_os_type = "arm-ubuntu-64"`
- **Network adapter**: Use `vmxnet3` for best performance
  ```hcl
  vmx_data = {
    "ethernet0.virtualdev" = "vmxnet3"
  }
  ```

#### ISO Source Verification
- Ensure ISO URL matches architecture in source block name
- Verify checksum file covers both architectures
- Check official Ubuntu Cloud Images: https://cloud-images.ubuntu.com/

### 4. Ubuntu Cloud Image Specifics

- **Cloud-init**: Use `http_directory` with user-data file
- **Autoinstall**: Boot command should reference cloud-init datasource
  ```hcl
  boot_command = [
    "<wait>",
    "autoinstall ds=nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/",
    "<enter>"
  ]
  ```
- **Guest tools**: Install appropriate tools
  - VirtualBox: Install VBox Guest Additions
  - VMware: Install open-vm-tools
- **Vagrant user**: Ensure passwordless sudo in cloud-init late-commands

### 5. Variables and Modularity

- **Use variables**: Extract common values to `variables.pkr.hcl`
- **Sensitive data**: Mark passwords/tokens as `sensitive = true`
- **Defaults**: Provide sensible defaults for all variables
- **Documentation**: Comment variable purposes

### 6. Output Format

Provide review findings in this structure:

```
## CRITICAL Issues
- [File:Line] Issue description
  Fix: Suggested code

## Warnings
- [File:Line] Issue description
  Recommendation: Suggested improvement

## Suggestions
- [File:Line] Best practice suggestion
  Example: Code example
```

## Examples

### Example 1: Missing Checksum
```
## CRITICAL Issues
- [virtualbox-amd64.pkr.hcl:3] ISO checksum not verified
  Fix: Add checksum verification
  ```hcl
  iso_checksum = "file:https://cloud-images.ubuntu.com/releases/24.04/release/SHA256SUMS"
  ```
```

### Example 2: Architecture Mismatch
```
## Warnings
- [vmware-arm64.pkr.hcl:8] Guest OS type incorrect for ARM64
  Current: guest_os_type = "ubuntu-64"
  Fix: guest_os_type = "arm-ubuntu-64"
```

### Example 3: Optimization Suggestion
```
## Suggestions
- [virtualbox-amd64.pkr.hcl:15] Enable headless mode for CI/CD
  Add: headless = true
```

## Reference

- [Packer VirtualBox Builder](https://developer.hashicorp.com/packer/plugins/builders/virtualbox/iso)
- [Packer VMware Builder](https://developer.hashicorp.com/packer/plugins/builders/vmware/iso)
- [Ubuntu Cloud Images](https://cloud-images.ubuntu.com/)
- [Vagrant Box Format](https://developer.hashicorp.com/vagrant/docs/boxes/format)
