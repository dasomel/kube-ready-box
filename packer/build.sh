#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 dasomel
set -e

#=========================================
# Vagrant Box Build Script
# dasomel/ubuntu-24.04
#=========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Detect platform
detect_platform() {
  local arch=$(uname -m)
  if [ "$arch" = "arm64" ]; then
    echo "arm64"
  elif [ "$arch" = "x86_64" ]; then
    echo "amd64"
  else
    echo "unknown"
  fi
}

PLATFORM=$(detect_platform)

show_usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Build dasomel/ubuntu-24.04 Vagrant boxes for multiple architectures and providers.

PLATFORM COMPATIBILITY:
  Current Platform: ${PLATFORM} ($(uname -m))

  Apple Silicon (ARM64):
    ✅ VirtualBox ARM64  (⚠️  Known boot_command issue)
    ✅ VMware ARM64      (Requires VMware Fusion)
    ❌ AMD64 builds      (x86 not supported)

  Intel Mac (x86):
    ✅ VirtualBox AMD64
    ✅ VMware AMD64
    ⚠️  ARM64 builds     (Limited support)

OPTIONS:
  all                 Build all boxes in parallel (VirtualBox + VMware, AMD64 + ARM64)
  virtualbox          Build all VirtualBox boxes in parallel (AMD64 + ARM64)
  vmware              Build all VMware boxes in parallel (AMD64 + ARM64)
  virtualbox-amd64    Build VirtualBox AMD64 box only
  virtualbox-arm64    Build VirtualBox ARM64 box only (⚠️  Apple Silicon issue)
  vmware-amd64        Build VMware AMD64 box only
  vmware-arm64        Build VMware ARM64 box only (requires Apple Silicon + VMware Fusion)
  init                Initialize Packer (install required plugins)
  validate            Validate Packer templates
  clean               Remove generated box files
  help                Show this help message

EXAMPLES:
  $0 init                    # Install Packer plugins
  $0 validate                # Validate all templates
  $0 virtualbox-amd64        # Build VirtualBox AMD64 box only
  $0 virtualbox              # Build all VirtualBox boxes in parallel
  $0 all                     # Build all 4 boxes in parallel

REQUIREMENTS:
  - Packer 1.8+
  - VirtualBox 7.1+ (for ARM64 support)
  - VMware Fusion (for VMware boxes)
  - 20GB+ free disk space per box
  - 4GB+ RAM recommended

KNOWN ISSUES:
  - VirtualBox ARM64 on Apple Silicon: boot_command scancode failures
  - See README.md for detailed workarounds

OUTPUT:
  Built boxes will be in: $SCRIPT_DIR/

EOF
}

init_packer() {
  echo "=== Initializing Packer ==="
  packer init .
  echo "Packer plugins installed successfully"
}

validate_templates() {
  echo "=== Validating Packer Templates ==="
  packer validate .
  echo "All templates are valid"
}

# Check ARM build compatibility and show warnings
check_arm_build() {
  local provider=$1
  local arch=$2

  # If building ARM64 on Apple Silicon, show warnings
  if [ "$arch" = "arm64" ] && [ "$PLATFORM" = "arm64" ]; then
    echo -e "${YELLOW}⚠️  ARM64 Build Warning${NC}"
    echo ""

    if [ "$provider" = "virtualbox" ]; then
      echo -e "${RED}KNOWN ISSUE: VirtualBox ARM64 on Apple Silicon${NC}"
      echo "Problem: VirtualBox ARM64 has keyboard input limitations"
      echo "Error: 'Failed to send a scancode' during boot_command"
      echo ""
      echo -e "${YELLOW}This build is LIKELY TO FAIL due to VirtualBox platform limitations.${NC}"
      echo ""
      echo "Workarounds:"
      echo "  1. Use Intel Mac for VirtualBox builds"
      echo "  2. Use VMware as alternative provider"
      echo "  3. Try manual installation instead of automated boot_command"
      echo ""
      read -p "Continue anyway? (y/N) " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Build cancelled by user"
        exit 0
      fi
    elif [ "$provider" = "vmware" ]; then
      echo -e "${YELLOW}Note: VMware ARM64 requires VMware Fusion on Apple Silicon${NC}"
      echo ""

      # Check if VMware Fusion is installed
      if [ ! -f "/Applications/VMware Fusion.app/Contents/Public/vmrun" ]; then
        echo -e "${RED}ERROR: VMware Fusion not found${NC}"
        echo "Please install VMware Fusion from: https://www.vmware.com/products/fusion.html"
        echo ""
        exit 1
      fi

      # Check if VMware Fusion services are running
      if ! pgrep -q "vmware"; then
        echo -e "${YELLOW}WARNING: VMware Fusion may not be running${NC}"
        echo "Common VMware ARM64 issues:"
        echo "  - VMware Fusion not started"
        echo "  - Permissions not granted"
        echo "  - VMware services not running"
        echo ""
        echo "Try starting VMware Fusion manually first:"
        echo "  open -a 'VMware Fusion'"
        echo ""
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
          echo "Build cancelled by user"
          exit 0
        fi
      fi
    fi
  fi

  # If building AMD64 on Apple Silicon, block it
  if [ "$arch" = "amd64" ] && [ "$PLATFORM" = "arm64" ]; then
    echo -e "${RED}❌ PLATFORM INCOMPATIBILITY${NC}"
    echo ""
    echo "Cannot build AMD64 (x86) boxes on Apple Silicon (ARM)."
    echo ""
    echo "Platform: $(uname -m)"
    echo "Requested: ${arch}"
    echo ""
    echo "AMD64 builds require Intel Mac or x86 CI/CD environment."
    echo ""
    exit 1
  fi
}

# Show post-failure help
show_failure_help() {
  local provider=$1
  local arch=$2
  local logfile=$3

  echo ""
  echo -e "${RED}=========================================="
  echo "Build Failed: ${provider} ${arch}"
  echo -e "==========================================${NC}"
  echo ""
  echo "Log file: ${logfile}"
  echo ""

  if [ "$arch" = "arm64" ] && [ "$PLATFORM" = "arm64" ]; then
    if [ "$provider" = "virtualbox" ]; then
      echo -e "${YELLOW}VirtualBox ARM64 Known Issues:${NC}"
      echo "  - Keyboard input (scancode) not supported"
      echo "  - boot_command fails on Apple Silicon"
      echo ""
      echo "Solutions:"
      echo "  1. Build on Intel Mac instead"
      echo "  2. Use VMware as alternative provider"
      echo "  3. Manual VM creation with pre-built image"
      echo ""
    elif [ "$provider" = "vmware" ]; then
      echo -e "${YELLOW}VMware ARM64 Common Issues:${NC}"
      echo "  - 'The operation was canceled' error"
      echo "  - VMware Fusion not running or no permissions"
      echo "  - VMware services not started"
      echo ""
      echo "Solutions:"
      echo "  1. Start VMware Fusion manually: open -a 'VMware Fusion'"
      echo "  2. Grant necessary permissions in System Settings"
      echo "  3. Restart VMware services:"
      echo "     sudo /Applications/VMware\\ Fusion.app/Contents/Library/services.sh --stop"
      echo "     sudo /Applications/VMware\\ Fusion.app/Contents/Library/services.sh --start"
      echo ""
    fi
  fi

  echo "Check the log file for detailed error messages:"
  echo "  tail -50 ${logfile}"
  echo ""
}

build_box() {
  local provider=$1
  local arch=$2

  # Check compatibility before building
  check_arm_build "$provider" "$arch"

  # Create logs directory if not exists
  mkdir -p logs

  # Generate log filename with datetime
  local datetime=$(date +"%Y%m%d-%H%M%S")
  local logfile="logs/build-${provider}-${arch}-${datetime}.log"

  # Determine source name based on provider
  local source_name=""
  if [ "$provider" = "virtualbox" ]; then
    source_name="virtualbox-iso.ubuntu-vbox-${arch}"
  elif [ "$provider" = "vmware" ]; then
    source_name="vmware-iso.ubuntu-vmware-${arch}"
  else
    echo "Error: Unknown provider '$provider'"
    exit 1
  fi

  echo ""
  echo "=========================================="
  echo "Building: ${provider} ${arch}"
  echo "Platform: ${PLATFORM}"
  echo "Source: ${source_name}"
  echo "Log: ${logfile}"
  echo "=========================================="
  echo ""

  # Run packer build and capture exit code
  # Note: Use PIPESTATUS to get packer's exit code, not tee's
  set +e  # Temporarily disable exit on error
  packer build -force -only="$source_name" . 2>&1 | tee "$logfile"
  local packer_exit_code=${PIPESTATUS[0]}
  set -e  # Re-enable exit on error

  echo ""

  if [ $packer_exit_code -eq 0 ]; then
    # Verify .box file was actually created
    local box_file=$(ls -t *.box 2>/dev/null | head -1)
    if [ -n "$box_file" ]; then
      echo -e "${GREEN}✅ Build SUCCESS: ${provider}-${arch}${NC}"
      echo "📝 Log saved to: ${logfile}"
      echo -e "${GREEN}📦 Box created: ${box_file}${NC}"
      ls -lh "$box_file"
      echo ""
      return 0
    else
      echo -e "${YELLOW}⚠️  Build completed but no .box file found${NC}"
      echo "📝 Log saved to: ${logfile}"
      echo "This may indicate a post-processor issue."
      echo ""
      return 1
    fi
  else
    echo -e "${RED}❌ Build FAILED: ${provider}-${arch}${NC}"
    echo "📝 Log saved to: ${logfile}"
    echo ""
    show_failure_help "$provider" "$arch" "$logfile"
    return 1
  fi
}

clean_output() {
  echo "=== Cleaning Output Files ==="
  rm -f *.box
  rm -rf output-*/
  rm -rf packer_cache/
  echo "Cleanup complete"
}

case "${1:-help}" in
  init)
    init_packer
    ;;
  validate)
    validate_templates
    ;;
  virtualbox-amd64)
    build_box virtualbox amd64
    ;;
  virtualbox-arm64)
    build_box virtualbox arm64
    ;;
  vmware-amd64)
    build_box vmware amd64
    ;;
  vmware-arm64)
    build_box vmware arm64
    ;;
  virtualbox)
    echo "Starting parallel VirtualBox builds..."
    build_box virtualbox amd64 &
    pid1=$!
    build_box virtualbox arm64 &
    pid2=$!

    echo "Waiting for builds to complete..."
    failed=0
    wait $pid1 || { echo "❌ VirtualBox AMD64 failed"; ((failed++)); }
    wait $pid2 || { echo "❌ VirtualBox ARM64 failed"; ((failed++)); }

    [ $failed -gt 0 ] && exit 1
    echo "✅ All VirtualBox builds complete"
    ;;
  vmware)
    echo "Starting parallel VMware builds..."
    build_box vmware amd64 &
    pid1=$!
    build_box vmware arm64 &
    pid2=$!

    echo "Waiting for builds to complete..."
    failed=0
    wait $pid1 || { echo "❌ VMware AMD64 failed"; ((failed++)); }
    wait $pid2 || { echo "❌ VMware ARM64 failed"; ((failed++)); }

    [ $failed -gt 0 ] && exit 1
    echo "✅ All VMware builds complete"
    ;;
  all)
    echo "Starting parallel builds for all 4 boxes..."
    echo ""

    # Launch all builds in parallel
    build_box virtualbox amd64 &
    pid_vbox_amd64=$!

    build_box virtualbox arm64 &
    pid_vbox_arm64=$!

    build_box vmware amd64 &
    pid_vmware_amd64=$!

    build_box vmware arm64 &
    pid_vmware_arm64=$!

    echo "All builds launched in parallel"
    echo "VirtualBox AMD64: PID $pid_vbox_amd64"
    echo "VirtualBox ARM64: PID $pid_vbox_arm64"
    echo "VMware AMD64: PID $pid_vmware_amd64"
    echo "VMware ARM64: PID $pid_vmware_arm64"
    echo ""
    echo "Waiting for all builds to complete..."
    echo ""

    # Wait for all builds and track failures
    failed=0
    wait $pid_vbox_amd64 || { echo "❌ VirtualBox AMD64 build failed"; ((failed++)); }
    wait $pid_vbox_arm64 || { echo "❌ VirtualBox ARM64 build failed"; ((failed++)); }
    wait $pid_vmware_amd64 || { echo "❌ VMware AMD64 build failed"; ((failed++)); }
    wait $pid_vmware_arm64 || { echo "❌ VMware ARM64 build failed"; ((failed++)); }

    echo ""
    echo "=========================================="
    if [ $failed -eq 0 ]; then
      echo "🎉 All 4 boxes built successfully!"
      echo "=========================================="
      ls -lh *.box
    else
      echo "⚠️  $failed build(s) failed!"
      echo "=========================================="
      echo "Check individual log files in logs/ directory"
      exit 1
    fi
    ;;
  clean)
    clean_output
    ;;
  help|--help|-h)
    show_usage
    ;;
  *)
    echo "Error: Unknown option '$1'"
    echo ""
    show_usage
    exit 1
    ;;
esac
