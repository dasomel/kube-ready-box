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
4. writes non-secret identity attestation metadata;
5. disables and removes itself.

The final cleanup removes SSH host private keys and source machine identity from the release image.

## Validation

```bash
tools/image-identity-security-check.sh /path/to/unpacked/rootfs
```

Two instances cloned from the same image must have different machine IDs and SSH host-key fingerprints. Snapshot/revert tests must be treated separately: reverting a snapshot intentionally reverts machine state, so production bootstrap should use a node-registration/duplicate-node guard before rejoining a cluster.

Secure Boot and TPM/vTPM are capability evidence, not requirements of the base box. A provider that cannot expose them must report unavailable rather than pretending they are enabled.
