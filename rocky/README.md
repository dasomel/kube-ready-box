# Rocky Linux Kubernetes-ready profile

Rocky Linux is a distro-specific implementation of the common Kubernetes readiness contract from `tools/node-readiness-attest.sh` and issue #13.

## Support policy

- Rocky Linux 9: **stable target** once the declared provider/architecture/filesystem matrix passes.
- Rocky Linux 10: **experimental target** until CPU/architecture and Kubernetes/runtime/network/storage matrix evidence is complete.

Rocky uses `dnf`, SELinux, firewalld and NetworkManager semantics rather than Ubuntu's apt/AppArmor/netplan model. The common evidence schema must not hide those differences.

## Preflight

`rocky/preflight.sh` checks SELinux enforcing state, firewalld/NetworkManager availability, cgroup v2, containerd SystemdCgroup, swap, kernel modules, sysctl, bpffs, chrony, CSI tools and filesystem.

Unsupported capabilities are `UNKNOWN`, never false-green.

## Provider/architecture matrix (#15)

| Provider | Arch | ext4 | xfs |
|---|---|---|---|
| VMware | arm64 | real `vagrant up` boot-verified | packer validate + `ksvalidator` only, boot not run |
| VirtualBox | arm64 | real `vagrant up` boot-verified (SELinux enforcing, sshd/chronyd/NetworkManager/firewalld active, disk on `/dev/sda`, machine-id/SSH host keys/Secure Boot-TPM capability correctly regenerated on first boot) | not built |
| VMware / VirtualBox | amd64 | not built (this repo's host is Apple Silicon; AMD64 needs an x86_64 build host) | not built |

VirtualBox ARM64 uses the same hand-built OVF/VMDK packaging as Ubuntu's `virtualbox-arm64.pkr.hcl`
(VirtualBox's own ARM64 OVF export doesn't work) — see `packer/templates/rocky-ovf.tpl` and
`packer/rocky-virtualbox-arm64.pkr.hcl`. `01-base-rocky.sh`'s `open-vm-tools`/`vmtoolsd` step is
guarded by `systemd-detect-virt` so it doesn't try to enable a VMware-only service on VirtualBox.

## Rocky 10 CPU policy

The profile detects the host CPU flags before treating Rocky 10 as supported. An x86_64-v3 requirement is represented as a capability decision; the profile does not silently enable `allowUnsupportedSystem`-style behavior.

## Release

Rocky artifacts must use the same immutable release evidence rules as Ubuntu: checksum, SBOM, license/security evidence, readiness attestation and rollback retention.
