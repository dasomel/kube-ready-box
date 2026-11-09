# Node storage readiness

`storage/node-storage-readiness.sh` reports filesystem, capacity/inode, mount propagation, LVM and representative NFS/iSCSI/cryptsetup/device-mapper capabilities using `kube-ready-storage/v1`.

The validator does not pretend that a tool being installed proves CSI mount/reconnect/expansion behavior. Those are explicit E2E tests and are represented as `UNKNOWN` until a test device/backend is supplied.

## Report fields

- `capacity_threshold`: `FAIL` when disk or inode usage of `/` is above 90%; `PASS` at or below 90%; `UNKNOWN` when a percentage is missing or non-numeric (for example `-` on filesystems without inode accounting).
- `growroot_evidence`: relays `/etc/vagrant-box/growroot.json` (`kube-ready-growroot/v1`, written by `packer/scripts/05-disk-tuning*.sh`). `status` `PASS` -> `PASS`, `FAIL` -> `FAIL`; file missing, unparseable, wrong schema, or `UNKNOWN` (first-boot growth not completed) -> `UNKNOWN`. Never mapped to `PASS` without an explicit `PASS`.

Fixture coverage: `tools/tests/node-storage-capacity-growroot-test.sh`.
