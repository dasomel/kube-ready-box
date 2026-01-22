#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 dasomel
#
# Generate SBOM (Software Bill of Materials) for the Vagrant box
# This script runs inside the VM during Packer build

set -e

echo "=== generate-sbom.sh: Generating SBOM ==="

SBOM_DIR="/etc/vagrant-box"
mkdir -p "$SBOM_DIR"

#=========================================
# 1. Install trivy (if not present)
#=========================================
if ! command -v trivy &> /dev/null; then
    echo "Installing trivy..."
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
fi

#=========================================
# 2. Generate SBOM in multiple formats
#=========================================
echo "Generating SPDX SBOM..."
trivy rootfs / --format spdx-json -o "$SBOM_DIR/sbom-spdx.json" 2>/dev/null || true

echo "Generating CycloneDX SBOM..."
trivy rootfs / --format cyclonedx -o "$SBOM_DIR/sbom-cyclonedx.json" 2>/dev/null || true

#=========================================
# 3. Generate package list (dpkg)
#=========================================
echo "Generating package list..."
dpkg-query -W -f='${Package}\t${Version}\t${License}\n' > "$SBOM_DIR/packages.txt" 2>/dev/null || \
dpkg-query -W -f='${Package}\t${Version}\n' > "$SBOM_DIR/packages.txt"

#=========================================
# 4. Generate simple manifest
#=========================================
echo "Generating manifest..."
cat <<EOF > "$SBOM_DIR/manifest.json"
{
  "name": "dasomel/ubuntu-24.04",
  "version": "$(cat /etc/vagrant-box/info.json 2>/dev/null | grep -o '"version"[^,]*' | cut -d'"' -f4 || echo "1.0.0")",
  "base_os": "Ubuntu 24.04 LTS",
  "architecture": "$(uname -m)",
  "kernel": "$(uname -r)",
  "build_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "sbom_generator": "trivy",
  "sbom_formats": ["spdx-json", "cyclonedx-json"],
  "package_count": $(dpkg-query -W | wc -l)
}
EOF

#=========================================
# 5. Set permissions
#=========================================
chmod 644 "$SBOM_DIR"/*.json "$SBOM_DIR"/*.txt 2>/dev/null || true

echo "SBOM files generated:"
ls -la "$SBOM_DIR"/sbom-*.json "$SBOM_DIR"/manifest.json "$SBOM_DIR"/packages.txt 2>/dev/null || true

echo "=== generate-sbom.sh: Complete ==="
