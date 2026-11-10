# Security response history

English | [한국어](security-response-ko.md)

This is a dated record of findings and responses, newest first. Trivy scans the package databases extracted from box disks and counts findings for which distro fixes are available. Zero fixable findings does not mean zero vulnerabilities; upstream-unfixed findings are outside that measure, and standalone binaries were outside it until the daily scan began extracting them. The 2026-11-08 section reports package/CVE pairs and links evidence for every released provider image. Earlier sections retain their original measurement scope and [November rebuild records](../research/evidence/2026-11.jsonl).

## 2026-11-08 — Daily Box CVE scan (#100) and v0.3.2 rebuild

| Finding and affected box | Status and fixed version | Evidence |
| --- | --- | --- |
| Ubuntu 24.04, published 0.3.1 (`ext4` and `xfs`, `vmware_desktop` arm64 and `virtualbox` amd64): HIGH 4 package/CVE findings (`CVE-2026-109518` in the `apt` family) / MEDIUM 21 fixable CVEs. | **Fixed in v0.3.2 / box 0.3.2 (2026-11-08):** 0 fixable CVEs (candidate box scanned locally with Trivy before release); `apt` 2.8.4ubuntu0.1, kernel 6.8.0-149-generic. | [Issue #100](https://github.com/dasomel/kube-ready-box/issues/100), [PR #98](https://github.com/dasomel/kube-ready-box/pull/98), [rebuild evidence](releases/v0.3.2-evidence.json) |
| Ubuntu 26.04, published 0.3.1 (`ext4` and `xfs`, `vmware_desktop` arm64 and `virtualbox` amd64): HIGH 3 package/CVE findings (`CVE-2026-109518` in the `apt` family) / MEDIUM 22 fixable CVEs. | **Fixed in v0.3.2 / box 0.3.2 (2026-11-08):** 0 fixable CVEs (candidate box scanned locally with Trivy before release); `apt` 3.2.1ubuntu0.1, kernel 7.0.0-43-generic. | [Issue #100](https://github.com/dasomel/kube-ready-box/issues/100), [PR #98](https://github.com/dasomel/kube-ready-box/pull/98), [rebuild evidence](releases/v0.3.2-evidence.json) |
| Rocky 9, published 0.1.1 (`ext4` and `xfs`, `vmware_desktop` arm64): HIGH 198 fixable package/CVE findings from kernel errata (fixed in 5.14.0-687.64.1 / 687.66.1), including CVE-2026-98432 (previously open-upstream for Rocky). | **Fixed in v0.3.2 / box 0.1.2 (2026-11-08):** 0 fixable CVEs (candidate box scanned locally with Trivy before release); kernel 5.14.0-687.66.1.el9_8.aarch64. | [Issue #100](https://github.com/dasomel/kube-ready-box/issues/100), [PR #98](https://github.com/dasomel/kube-ready-box/pull/98), [rebuild evidence](releases/v0.3.2-evidence.json) |
| Ubuntu 24.04/26.04: CVE-2026-98432. | **Version match confirmed; distro tracking pending:** candidate kernel packages `6.8.0-149.149` / `7.0.0-43.43` match the fix builds identified by Canonical. The CVE JSON checked on 2026-11-08 still marks both LTS releases `pending`. A fixable-only scan does not turn that tracking status into PASS. | [Canonical fix-build guidance](https://ubuntu.com/blog/fixes-available-in-proposed-pocket-for-cve-2026-98432), [official CVE JSON](https://ubuntu.com/security/cves/CVE-2026-98432.json), [rebuild evidence](releases/v0.3.2-evidence.json) |

Triggered by the daily Box CVE scan ([PR #98](https://github.com/dasomel/kube-ready-box/pull/98)), which opened [issue #100](https://github.com/dasomel/kube-ready-box/issues/100) on 2026-11-08. Release `v0.3.2` uses the recorded source revisions and unchanged pinned executable inputs; download error handling was improved in PR #101; it also ships the `license-info.sh` catalog-URL fix from [PR #94](https://github.com/dasomel/kube-ready-box/pull/94) ([c630456](https://github.com/dasomel/kube-ready-box/commit/c630456)), pointing `/etc/vagrant-box/info.txt` at the GitHub Pages catalog instead of the retired Vagrant Cloud page. Build and boot-verification sources match 0.3.1: `vmware_desktop` arm64 built locally and boot-verified on VMware Fusion, `virtualbox` amd64 built and boot-tested by `.github/workflows/build-amd64.yml`. NixOS 0.2.2 is unchanged and stays in `v0.3.0`.

## 2026-11-01 — Box package and kernel remediation

| Finding and affected box | Status and fixed version | Evidence |
| --- | --- | --- |
| Rocky 9, published 0.1.0 line: CRITICAL 5 / HIGH 411 / MEDIUM 22 (438 total) fixable CVEs. The installer kernel 5.14.0-687.10.1 contributed 399 CVEs because the build had not rebooted after updating. | **Fixed in v0.3.0 (2026-11-01):** 0 fixable CVEs; only kernel 5.14.0-687.61.1.el9_8 was observed. | [Kernel prune commit c2e6de3](https://github.com/dasomel/kube-ready-box/commit/c2e6de3), [PR #84](https://github.com/dasomel/kube-ready-box/pull/84), [Rocky xfs build fix PR #86](https://github.com/dasomel/kube-ready-box/pull/86) |
| Ubuntu 26.04, local pre-release build: CRITICAL 2 / HIGH 104 / MEDIUM 866 / LOW 169 fixable CVEs. | **Fixed in v0.3.0 (2026-11-01):** 0 fixable CVEs; kernel 7.0.0-42, curl 8.18.0-1ubuntu2.8, OpenSSL 3.5.5-1ubuntu3.7. | [PR #84](https://github.com/dasomel/kube-ready-box/pull/84), [rebuild evidence](../research/evidence/2026-11.jsonl) |
| Ubuntu 24.04, rebuilt box. | **Fixed in v0.3.0 (2026-11-01):** 0 fixable CVEs; kernel 6.8.0-147. | [Rebuild evidence](../research/evidence/2026-11.jsonl), [PR #84](https://github.com/dasomel/kube-ready-box/pull/84) |
| NixOS published 0.2.0, kernel 6.18.36: CVE-2026-98432 (Linux IPv4 TCP use-after-free). | **Fixed in 0.2.1 and 0.2.2:** upstream fix e3f33b0a1d89 is present from Linux 6.18.56. Version 0.2.2 uses kernel 6.18.60 and OpenSSH 10.6p1, which fixes CVE-2026-106552 and CVE-2026-106583. Published 0.2.0 remains affected. | [NixOS update 169bb21](https://github.com/dasomel/kube-ready-box/commit/169bb21), [kernel.org ChangeLog-6.18.56](https://cdn.kernel.org/pub/linux/kernel/v6.x/ChangeLog-6.18.56) |
| Ubuntu 24.04/26.04 and Rocky 9: CVE-2026-98432. | **Open-upstream:** no USN or RHSA at the time of this record. Rebuild when distro fixes are released. | [Upstream fix e3f33b0a1d89](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=e3f33b0a1d89) |
| gVisor 20260817.0: CVE-2026-95702 and Go standard-library CVE-2026-78660, CVE-2026-97031, CVE-2026-111943. | **Fixed in rebuilt boxes:** gVisor 20261026.0. Review caught a sidecar regression: `runsc` needs `gvisor-bin/gvisor_sentry`. | [Upgrade 4d579ce](https://github.com/dasomel/kube-ready-box/commit/4d579ce), [build inputs](build-inputs.md) |
| `yq` v4.44.3 (Go 1.22.5). | **Mitigated / accepted-exception:** upgraded to v4.54.1 (Go 1.27.1). Remaining Go CVEs require Go >= 1.27.3; reachability in `yq` is unverified. | [Upgrade 4d579ce](https://github.com/dasomel/kube-ready-box/commit/4d579ce), [build-input exception](build-inputs.md) |
| `dool` 1.3.8: CVE-2026-56651 and CVE-2026-56652. | **Accepted-exception:** no fixed upstream release; upgrade when one is available. | [Build-input exception](build-inputs.md) |
| `yq` v4.54.1 (go1.27.1, x/net v0.59.0): HIGH CVE-2026-78661, CVE-2026-78667, CVE-2026-78669 (plus the accepted CVE-2026-78660/97031/111943), found by the binary scan ([PR #109](https://github.com/dasomel/kube-ready-box/pull/109)). | **Fixed in v0.3.3 / Ubuntu boxes 0.3.3 and Rocky boxes 0.1.3 (2026-11-10):** `yq` v4.54.3 (go1.27.3, x/net v0.62.0), fixed in source by [PR #111](https://github.com/dasomel/kube-ready-box/pull/111). All shipped v0.3.2 boxes contained v4.54.1. Every candidate box was scanned with Trivy 0.76.0 (OS packages and standalone binaries, `yq` included): 0 fixable CVEs. | [Build inputs](build-inputs.md), [PR #109](https://github.com/dasomel/kube-ready-box/pull/109), [Release v0.3.3](https://github.com/dasomel/kube-ready-box/releases/tag/v0.3.3), [issue #112](https://github.com/dasomel/kube-ready-box/issues/112), [rebuild evidence](releases/v0.3.3-evidence.json) |

Box-size work followed the rebuilds ([1d3abd3](https://github.com/dasomel/kube-ready-box/commit/1d3abd3)); a Rocky first-boot `sshd-keygen` ordering race was fixed in [549239d](https://github.com/dasomel/kube-ready-box/commit/549239d). The intermittent VMware build SSH disconnect ([mistakes log #26](mistakes-log.md)) is a build reliability issue, not a box vulnerability.

## 2026-11-01 — Build input supply chain

| Finding | Status and response | Evidence |
| --- | --- | --- |
| Floating `hashicorp/setup-packer@main` action. | **Fixed:** pinned to the v3.4.0 commit. | [a1d84e4](https://github.com/dasomel/kube-ready-box/commit/a1d84e4) |
| Unpinned-input guard scanned only two directories; a comment ending in backslash could hide the next fetch. | **Fixed:** expanded scanning and closed the parser gap. | [35a5606](https://github.com/dasomel/kube-ready-box/commit/35a5606), [45c3ec4](https://github.com/dasomel/kube-ready-box/commit/45c3ec4) |
| Packer plugin initialization lacked authenticated GitHub requests. | **Fixed:** authenticated `packer init`. | [PR #85](https://github.com/dasomel/kube-ready-box/pull/85), [40aa827](https://github.com/dasomel/kube-ready-box/commit/40aa827) |

## 2026-10-31 — Evidence and release gates

| Finding | Status and response | Evidence |
| --- | --- | --- |
| Release promotion accepted FAIL/UNKNOWN reports and missing or wrong hashes; `SHA256SUMS` paths could escape through `../` or symlinks. | **Fixed:** promotion validates evidence status and artifact hashes. | [PR #83](https://github.com/dasomel/kube-ready-box/pull/83), [243ddb8](https://github.com/dasomel/kube-ready-box/commit/243ddb8) |
| License gate hashed host copyright files under `ROOT=`; absolute in-image symlinks escaped `ROOT`. | **Fixed:** hashes are taken from the image root. | [a41f9e0](https://github.com/dasomel/kube-ready-box/commit/a41f9e0) |
| Verifier ignored mistyped flags; readiness drift could report false `NO_DRIFT`; airgap verification accepted incomplete bundles. | **Fixed:** reject invalid flags, stale drift evidence, and incomplete bundles. | [7c69e74](https://github.com/dasomel/kube-ready-box/commit/7c69e74), [5780f9d](https://github.com/dasomel/kube-ready-box/commit/5780f9d), [258535a](https://github.com/dasomel/kube-ready-box/commit/258535a) |

## Distribution and user action

Vagrant Cloud (HCP Vagrant) is ending service. Older published versions remain there until 2026-12-31 and will not receive fixes. Patched boxes are distributed through GitHub Release v0.3.0 (released 2026-11-01) and the Pages catalog. Users of published 0.2.0, 1.1.0, or 0.1.0 boxes should move to its boxes or run `apt`/`dnf` upgrade and reboot. This repository record does not independently verify each remote release asset.

## How we respond

We scan package databases extracted from box disks with Trivy, rebuild with a full package upgrade, cross-review changes, boot-verify rebuilt images, and publish patched boxes. Findings without an upstream fix stay open until a fixed distro package can be rebuilt. To catch those fixes, the [Box CVE scan](../.github/workflows/box-cve-scan.yml) workflow runs daily (`tools/box-cve-scan.sh`): it downloads each shipped box through its Pages catalog, verifies the checksum, extracts the dpkg/rpm database read-only, together with an allowlist of standalone binaries installed outside the package manager (`yq`, gVisor `runsc`/shim/`gvisor-bin`), and counts fixable CVEs with Trivy, including Go stdlib/module CVEs in those binaries. `summary.json` lists the binaries scanned. Findings already documented as accepted exceptions in [build-inputs.md](build-inputs.md) are suppressed through `tools/box-cve-scan.trivyignore.yaml` (scoped per binary, with an expiry date after which the scan fails again) and are still listed under `accepted` in the summary. A CRITICAL or HIGH finding fails the run, which is the rebuild trigger. NixOS has no dpkg/rpm database and is reported UNKNOWN, not PASS. Local rebuild records are in [2026-11.jsonl](../research/evidence/2026-11.jsonl).

## Reporting

Report suspected vulnerabilities privately using the process in [SECURITY.md](../SECURITY.md).
