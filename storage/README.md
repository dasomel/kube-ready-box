# Node storage readiness

`storage/node-storage-readiness.sh` reports filesystem, capacity/inode, mount propagation, LVM and representative NFS/iSCSI/cryptsetup/device-mapper capabilities using `kube-ready-storage/v1`.

The validator does not pretend that a tool being installed proves CSI mount/reconnect/expansion behavior. Those are explicit E2E tests and are represented as `UNKNOWN` until a test device/backend is supplied.
