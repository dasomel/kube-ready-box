# VM Identity and SSH Security Profile

A Vagrant build image and a production VM artifact have different SSH transport requirements.

## Build/Vagrant profile

The build retains the Vagrant user's public transport key so Packer/Vagrant can provision the image. This is a development/test transport profile, not a production trust model.

## Hardened profile

Set `KUBE_READY_HARDENED_SSH=1` during final cleanup to mark the image as hardened and remove the Vagrant user's insecure `authorized_keys`. The operator must inject an explicit production key or other supported access mechanism before boot.

## First boot

`98-first-boot-identity.sh` installs a one-shot systemd service that:

1. regenerates `/etc/machine-id` if absent;
2. regenerates SSH host keys with `ssh-keygen -A`;
3. removes the Vagrant insecure authorized key when hardened mode is enabled;
4. detects Secure Boot and TPM/vTPM capability (see below);
5. writes non-secret identity attestation metadata;
6. disables and removes itself.

This provisioner is wired into all four base templates
(`virtualbox-{amd64,arm64}.pkr.hcl`, `vmware-{amd64,arm64}.pkr.hcl`) as
`scripts/98-first-boot-identity.sh`, immediately before `99-cleanup.sh` — the
4-template rule applies to it like any other provisioner.

The final cleanup removes SSH host private keys and source machine identity from the release image.

## Secure Boot / TPM capability reporting

Secure Boot and TPM/vTPM are capability evidence, not requirements of the base box: the
provisioner reports each as one of `supported` / `partial` / `unavailable` rather than assuming
a provider exposes them, into `/etc/vagrant-box/identity-attestation.json`:

```json
{
  "secure_boot": {"status": "unavailable", "detail": "not booted via UEFI (BIOS/legacy boot)"},
  "tpm": {"status": "unavailable", "detail": "no TPM/vTPM device exposed by hypervisor"}
}
```

Detection method:

- **Secure Boot**: reads the `SecureBoot` UEFI variable directly from
  `/sys/firmware/efi/efivars` (byte 5, after the 4-byte attribute header). No UEFI firmware →
  `unavailable`. UEFI present but the variable isn't exposed → `unavailable`. Variable present
  and `0` → `partial` (firmware supports it, hypervisor/guest has it disabled). Variable present
  and `1` → `supported`.
- **TPM/vTPM**: looks for `/dev/tpmrm0` or `/dev/tpm0`. Neither present → `unavailable`. Present
  but `/sys/class/tpm/tpm0/tpm_version_major` doesn't report a version → `partial` (device node
  exists, driver not fully bound). Version reported → `supported`.

Both hypervisors this repo targets (VirtualBox, VMware Fusion) typically report `unavailable` for
both by default — that is a correct, honest result, not a bug. `supported`/`partial` require the
operator to have explicitly enabled EFI Secure Boot or attached a vTPM at the hypervisor level.

## Validation

```bash
tools/image-identity-security-check.sh /path/to/unpacked/rootfs
```

Two instances cloned from the same image must have different machine IDs and SSH host-key fingerprints. Snapshot/revert tests must be treated separately: reverting a snapshot intentionally reverts machine state, so production bootstrap should use a node-registration/duplicate-node guard before rejoining a cluster.

Secure Boot and TPM/vTPM are capability evidence, not requirements of the base box. A provider that cannot expose them must report unavailable rather than pretending they are enabled.
