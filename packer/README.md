# Packer Build Configuration

This directory contains Packer templates to build **dasomel/ubuntu-24.04** Vagrant boxes for multiple architectures and providers.

## Directory Structure

```
packer/
├── build.sh                    # Build automation script
├── plugins.pkr.hcl             # Plugins and shared variables
├── virtualbox-amd64.pkr.hcl    # VirtualBox AMD64 template
├── virtualbox-arm64.pkr.hcl    # VirtualBox ARM64 template
├── vmware-amd64.pkr.hcl        # VMware AMD64 template
├── vmware-arm64.pkr.hcl        # VMware ARM64 template
├── templates/
│   ├── ovf.tpl                 # VirtualBox OVF template (ARM64)
│   ├── metadata.tpl            # Vagrant metadata template
│   └── vagrantfile.tpl         # Vagrant box Vagrantfile template
├── http/
│   ├── autoinstall/            # ISO 설치용 (Ubuntu Server Subiquity)
│   │   ├── user-data           # Autoinstall config
│   │   └── meta-data           # Instance metadata
│   └── cloud-init/             # Cloud Image용
│       ├── user-data           # Cloud-config
│       └── meta-data           # Instance metadata
└── scripts/
    ├── 01-base.sh              # Package updates
    ├── 02-os-tuning.sh         # Kernel/resource tuning
    ├── 03-os-packages.sh       # Recommended packages
    ├── 04-k8s-prereq.sh        # K8s prerequisites
    ├── 05-disk-tuning.sh       # Disk I/O optimization
    ├── 06-nic-tuning.sh        # Network optimization
    ├── ubuntu2404-tuning.sh    # Ubuntu 24.04 specific
    ├── 07-check-tuning.sh      # Verification
    ├── license-info.sh         # License installation
    ├── generate-sbom.sh        # SBOM generation
    └── 99-cleanup.sh           # Pre-packaging cleanup
```

## Build Matrix

| Provider      | AMD64 | ARM64 | Requirements                    |
|---------------|-------|-------|---------------------------------|
| VirtualBox    | ✅    | ✅    | VirtualBox 7.1+ (ARM64)         |
| VMware Fusion | ✅    | ✅    | VMware Fusion (Apple Silicon)   |

### Platform Compatibility

**On Apple Silicon Macs (M1/M2/M3)**:
- ✅ **Supported**: VirtualBox ARM64, VMware ARM64
- ❌ **Not Supported**: AMD64 builds (x86 virtualization not available)

**On Intel Macs (x86)**:
- ✅ **Supported**: VirtualBox AMD64, VMware AMD64
- ⚠️ **AMD64 builds via GitHub Actions** recommended

## Prerequisites

### Software Requirements

- **Packer** 1.8+: `brew install packer`
- **VirtualBox** 7.1+: https://www.virtualbox.org/wiki/Downloads
- **VMware Fusion**: https://www.vmware.com/products/fusion.html

### System Requirements

- **Disk Space**: 20GB+ per box
- **Memory**: 4GB+ RAM recommended
- **Network**: Internet connection for ISO download

## Quick Start

### 1. Initialize Packer Plugins

```bash
cd packer
packer init .
```

### 2. Validate Templates

```bash
packer validate .
```

### 3. Build Boxes

**For Apple Silicon (M1/M2/M3)**:
```bash
# VMware (recommended - fastest)
packer build -only='vmware-iso.ubuntu-vmware-arm64' .

# VirtualBox
packer build -only='virtualbox-iso.ubuntu-vbox-arm64' .
```

**For Intel Macs (or GitHub Actions)**:
```bash
# VirtualBox AMD64
packer build -only='virtualbox-iso.ubuntu-vbox-amd64' .

# VMware AMD64
packer build -only='vmware-iso.ubuntu-vmware-amd64' .
```

## Configuration Variables

Variables are defined in `plugins.pkr.hcl`:

| Variable | Default | Description |
|----------|---------|-------------|
| `cpus` | 2 | CPU cores |
| `memory` | 2048 | RAM in MB |
| `disk_size` | 20000 | Disk size in MB |
| `headless` | true | Run without GUI |

Override at build time:
```bash
packer build \
  -var 'cpus=4' \
  -var 'memory=4096' \
  -var 'headless=false' \
  -only='vmware-iso.ubuntu-vmware-arm64' \
  .
```

## Output Files

Built boxes are saved in the `output-vagrant/` directory:

- `output-vagrant/ubuntu-24.04-virtualbox-amd64.box`
- `output-vagrant/ubuntu-24.04-virtualbox-arm64.box`
- `output-vagrant/ubuntu-24.04-vmware-amd64.box`
- `output-vagrant/ubuntu-24.04-vmware-arm64.box`

## Provisioning Scripts

Scripts run in order:

1. **01-base.sh**: Update packages, install essentials
2. **02-os-tuning.sh**: Kernel parameters (sysctl), resource limits
3. **03-os-packages.sh**: Performance/diagnostic tools
4. **04-k8s-prereq.sh**: Disable swap, load kernel modules, network settings
5. **05-disk-tuning.sh**: I/O scheduler, read-ahead, noatime
6. **06-nic-tuning.sh**: NIC ring buffer, offloading
7. **ubuntu2404-tuning.sh**: Ubuntu 24.04 specific (THP, systemd-oomd)
8. **07-check-tuning.sh**: Verify all settings
9. **license-info.sh**: Install license/box info
10. **generate-sbom.sh**: Generate SBOM files
11. **99-cleanup.sh**: Clean logs, caches, prepare for packaging

## Testing Built Boxes

```bash
# Add box locally
vagrant box add --name test/ubuntu-24.04 output-vagrant/ubuntu-24.04-vmware-arm64.box

# Create test directory
mkdir test && cd test

# Create Vagrantfile
cat > Vagrantfile <<EOF
Vagrant.configure("2") do |config|
  config.vm.box = "test/ubuntu-24.04"
  config.vm.provider "vmware_desktop" do |v|
    v.vmx["memsize"] = "2048"
    v.vmx["numvcpus"] = "2"
  end
end
EOF

# Test box
vagrant up
vagrant ssh -c "uname -a"
vagrant destroy -f
```

## Cleanup

```bash
# Remove built boxes and cache
rm -f *.box
rm -rf output-*/
rm -rf packer_cache/
```

## Troubleshooting

### Apple Silicon Platform Errors

**Error**: `Cannot run the machine because its platform architecture x86 is not supported on ARM`

**Solution**: Only build ARM64 boxes on Apple Silicon:
```bash
packer build -only='vmware-iso.ubuntu-vmware-arm64' .
```

### VirtualBox ARM64 OVF Import Error

**Error**: `<vbox:Machine> element in OVF contains a medium attachment...`

**Solution**: The `virtualbox-arm64.pkr.hcl` template uses a custom OVF generation process with VirtualBox 7.x compatible format. Ensure you're using the latest templates.

### Build Hangs at Boot

**Solutions**:
- Set `headless = false` to see boot screen
- Verify cloud-init configuration in `http/autoinstall/user-data`
- Check VM console for errors

## GitHub Actions

AMD64 builds are automated via GitHub Actions:

```bash
# Trigger manually
gh workflow run build-amd64.yml

# Or push a tag
git tag v1.0.0
git push origin v1.0.0
```

## License

MIT License - See `../LICENSE` for details
