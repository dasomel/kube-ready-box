# Security response history

English | [한국어](security-response-ko.md)

This is a dated record of findings and responses, newest first. Scan counts below are **unique CVE IDs for which a fixed package version was available**, measured with Trivy against package databases extracted from box disks. Zero in that measure does not mean zero vulnerabilities: upstream-unfixed findings remain. The counts are local rebuild measurements, not a claim that every published provider image was scanned. These counts come from a Trivy rootfs scan of package databases extracted from the box disks on 2026-11-01 (session measurement, raw output not committed). Kernel and package versions below were observed in boot verification of the rebuilt boxes on 2026-11-01. The rebuild records are in [2026-11.jsonl](../research/evidence/2026-11.jsonl) ([first batch](https://github.com/dasomel/kube-ready-box/commit/325f107), [second batch](https://github.com/dasomel/kube-ready-box/commit/5528164)).

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

We scan package databases extracted from box disks with Trivy, rebuild with a full package upgrade, cross-review changes, boot-verify rebuilt images, and will publish patched boxes. Findings without an upstream fix stay open until a fixed distro package can be rebuilt. Local rebuild records are in [2026-11.jsonl](../research/evidence/2026-11.jsonl).

## Reporting

Report suspected vulnerabilities privately using the process in [SECURITY.md](../SECURITY.md).
