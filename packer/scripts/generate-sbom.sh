#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
set -euo pipefail

SBOM_DIR="/etc/vagrant-box"
mkdir -p "$SBOM_DIR"

. /etc/os-release
ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
KERNEL="$(uname -r)"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# SBOM generation is deliberately offline. The image build must provide the
# scanner binary/DB in advance (for example through the air-gap bundle).
if command -v trivy >/dev/null 2>&1; then
  trivy rootfs / --offline-scan --format spdx-json -o "$SBOM_DIR/sbom-spdx.json"
  trivy rootfs / --offline-scan --format cyclonedx -o "$SBOM_DIR/sbom-cyclonedx.json"
else
  echo "trivy not installed; generating deterministic dpkg inventory only"
fi

dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\t${Status}\n' | sort > "$SBOM_DIR/packages.txt"
dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' | sort > "$SBOM_DIR/components.tsv"

# Record kernel/modules/firmware as release evidence in addition to packages.
{
  echo -e "kernel\t${KERNEL}"
  find /lib/modules/"$KERNEL" -type f -printf '%p\t%k KB\n' 2>/dev/null | sort || true
  find /lib/firmware -type f -printf '%p\t%k KB\n' 2>/dev/null | sort || true
} > "$SBOM_DIR/kernel-modules-firmware.tsv"

# #28 portfolio provenance (Narwhal #161 SBOM metadata minimum set):
# artifact/source/supplier/license are static to this repo; commit_sha/
# build_id/workflow_run/version are threaded in by packer/build.sh via
# Packer's PKR_VAR_* mechanism (see packer/plugins.pkr.hcl) and land here
# as plain env vars set on the shell provisioner. Manual `packer build`
# runs outside build.sh fall back to the pkr.hcl variable defaults
# ("unknown"/"local"/"0.0.0-dev"), not silently-empty fields.
cat > "$SBOM_DIR/manifest.json" <<EOF
{
  "schema_version": 3,
  "artifact": "dasomel/ubuntu-${VERSION_ID}",
  "name": "dasomel/ubuntu-${VERSION_ID}",
  "base_os": "Ubuntu ${VERSION_ID}",
  "architecture": "${ARCH}",
  "kernel": "${KERNEL}",
  "build_date": "${BUILD_DATE}",
  "timestamp": "${BUILD_DATE}",
  "sbom_generator": "$(command -v trivy >/dev/null 2>&1 && trivy version --format json 2>/dev/null | tr '\n' ' ' || echo 'offline-dpkg-inventory')",
  "sbom_formats": ["spdx-json", "cyclonedx-json", "dpkg-tsv"],
  "package_count": $(dpkg-query -W | wc -l),
  "source": "https://github.com/dasomel/kube-ready-box",
  "supplier": "dasomel",
  "license": "MIT",
  "version": "${KUBE_READY_BOX_VERSION:-unknown}",
  "provenance": {
    "commit_sha": "${KUBE_READY_COMMIT_SHA:-unknown}",
    "build_id": "${KUBE_READY_BUILD_ID:-unknown}",
    "workflow_run": "${KUBE_READY_WORKFLOW_RUN:-unknown}"
  }
}
EOF

# Link image-level inventory to the exact evidence generated in this build.
sha256sum "$SBOM_DIR"/packages.txt "$SBOM_DIR"/components.tsv "$SBOM_DIR"/kernel-modules-firmware.tsv > "$SBOM_DIR/inventory-SHA256SUMS"
chmod 0644 "$SBOM_DIR"/* 2>/dev/null || true

echo "=== generate-sbom.sh: offline inventory complete ==="
ls -la "$SBOM_DIR"/manifest.json "$SBOM_DIR"/packages.txt "$SBOM_DIR"/inventory-SHA256SUMS
