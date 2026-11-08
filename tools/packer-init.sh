#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
set -euo pipefail

# CI helper for Linux AMD64 runners. Run from packer/, like packer init itself.
if packer init .; then
  exit 0
fi

# D10: Packer's VMware asset download repeatedly returned HTTP 504.
# Use the same pinned release through GitHub's API, checking its archive
# digest before execution. Cost: extra API calls; remove when upstream recovers.
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]]
version=$(awk '/vmware =/{found=1;next} found && /version =/{sub(/.*"= */, ""); sub(/".*/, ""); print; exit}' plugins.pkr.hcl)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
archive="packer-plugin-vmware_v${version}_x5.0_linux_amd64.zip"
sums="packer-plugin-vmware_v${version}_SHA256SUMS"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
gh release download "v${version}" --repo vmware/packer-plugin-vmware \
  --pattern "$archive" --pattern "$sums" --dir "$stage"
(
  cd "$stage"
  awk -v archive="$archive" '$2 == archive {print}' "$sums" > archive.sha256
  test -s archive.sha256
  sha256sum --check archive.sha256
  unzip -q "$archive"
  packer plugins install --path "./${archive%.zip}" github.com/vmware/vmware
)
packer init .
