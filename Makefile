# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
#
# Common Make target vocabulary for the Dasomel OSS Portfolio
# (Narwhal #161): help, fmt, lint, test, security, license, sbom, build,
# package, e2e, clean, release. Each target here is a thin wrapper around
# this repo's existing tools -- it does not reimplement anything, it just
# gives kube-ready-box the same entry-point vocabulary as the other OSS
# repos in the portfolio while staying fully standalone buildable/
# releasable on its own (per #28/#161's "common principle": standard
# vocabulary, not forced implementation).
#
# UBUNTU_VERSION/FILESYSTEM select the Ubuntu build target for `build`/
# `package`/`e2e`; VERSION selects the release-evidence version for
# `release`. All default to this repo's existing conventions.

UBUNTU_VERSION ?= 24.04
FILESYSTEM ?= ext4
VERSION ?= 0.2.3

.PHONY: help fmt lint test security license sbom build package e2e clean release

help:
	@echo "kube-ready-box common targets (Narwhal #161 portfolio vocabulary):"
	@echo "  make fmt      - packer fmt -check (Packer templates)"
	@echo "  make lint     - shellcheck + bash -n + actionlint (if installed)"
	@echo "  make test     - Rust verifier build/test + contract JSON smoke"
	@echo "  make security - unpinned build-input guard (#30)"
	@echo "  make license  - license gate against dpkg on ROOT= (default: this host)"
	@echo "  make sbom     - SBOM/package-inventory guidance (generated inside the guest at build time)"
	@echo "  make build UBUNTU_VERSION=24.04 FILESYSTEM=ext4 - build all boxes for one version/filesystem"
	@echo "  make package  - alias for build (Packer's vagrant post-processor packages in the same run)"
	@echo "  make e2e      - boot-test built boxes (test-vm/matrix.sh)"
	@echo "  make clean    - remove generated box/output files"
	@echo "  make release VERSION=0.2.3 ACTION=init|promote|rollback|verify - tools/release-promote.sh"
	@echo ""
	@echo "make license queries dpkg directly (see tools/sbom-license-gate.sh) -- run it"
	@echo "inside a guest/CI Linux host (ROOT=/, the default) or point ROOT= at a mounted"
	@echo "box image's filesystem. make sbom's evidence is likewise generated INSIDE the"
	@echo "guest during provisioning, not on this host before a box exists."

fmt:
	cd packer && packer fmt -check -diff .

lint:
	find packer/scripts nixos rocky security network storage time observability tools rust \
	  -type f -name '*.sh' -print0 | xargs -0 -r shellcheck --severity=warning
	bash -n tools/*.sh network/*.sh storage/*.sh time/*.sh security/*.sh observability/*.sh rocky/*.sh nixos/*.sh packer/scripts/*.sh
	@if command -v actionlint >/dev/null 2>&1; then \
	  actionlint .github/workflows/*.yml; \
	else \
	  echo "actionlint not installed, skipping (see https://github.com/rhysd/actionlint)"; \
	fi

test:
	cd rust/kube-ready-verifier && cargo check --locked --offline && cargo build --release --locked --offline && bash tests/cli_contract.sh
	CONTRACT_OUTPUT=/tmp/kube-ready-contracts.json bash tools/kube-ready-contracts.sh
	python3 -m json.tool /tmp/kube-ready-contracts.json >/dev/null

security:
	bash tools/unpinned-input-guard.sh

# ROOT defaults to tools/sbom-license-gate.sh's own default (the running
# system) -- override to point at a mounted/extracted box image instead.
license:
	ROOT=$(ROOT) bash tools/sbom-license-gate.sh

sbom:
	@echo "SBOM generation runs INSIDE the guest during provisioning:"
	@echo "  packer/scripts/generate-sbom.sh -> /etc/vagrant-box/{manifest.json,packages.txt,sbom-spdx.json,sbom-cyclonedx.json}"
	@echo "There is no host-side SBOM to generate before a box exists -- build one first (make build),"
	@echo "then inspect its evidence via /etc/vagrant-box/ inside the running box."

build:
	cd packer && UBUNTU_VERSION=$(UBUNTU_VERSION) ./build.sh all --fs=$(FILESYSTEM) --version=$(UBUNTU_VERSION)

package: build

e2e:
	cd test-vm && bash matrix.sh

clean:
	cd packer && ./build.sh clean

release:
	VERSION=$(VERSION) bash tools/release-promote.sh $(ACTION)
