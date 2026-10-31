# smolvm as a complementary validation target (#54)

smolvm is a libkrun microVM that boots its own libkrunfw guest kernel. It is a **complementary** target for fast, OCI-based checks. It does not boot the Kube Ready Box image, so it can never prove image conformance.

Status: **Phase A (this document) only.** Phase B (optional harness, pinned fixtures, version capture) needs smolvm installed, which is a human decision and has not been done. Phase C (compare with #11/#29) and Phase D (custom kernel) are not started. Anything said here about smolvm itself (flags, versions, how it exposes devices) is **unverified**; nothing was run.

## Scope rule

A check is valid in smolvm only if its result depends on userspace the image ships or on generic Linux behavior any recent kernel provides. If it depends on the image's kernel build, boot chain, init system as PID 1, or the hypervisor's devices, it is not valid.

- **valid**: the result would be the same on any kernel that offers the interface.
- **non-equivalent**: the check runs and may print PASS/FAIL, but it observes the libkrunfw kernel, so the result says nothing about the image kernel.
- **invalid**: the check cannot run meaningfully or measures a property that does not exist in the guest.

## Applicability matrix

Ids are those emitted by each producer today. Verdicts are by reasoning from what the check reads; none was observed under smolvm.

### `tools/node-readiness-attest.sh` (`kube-ready-readiness/v1`)

| Ids | Verdict | Reason |
|---|---|---|
| `architecture` | valid | CPU architecture of the guest; fine if it matches the target arch. |
| `filesystem` | non-equivalent | Root filesystem type of the microVM, not the image's ext4/xfs/btrfs. |
| `swap` | non-equivalent | Guest kernel/VM config decides swap, not the image's fstab. |
| `cgroup_v2` | non-equivalent | Depends on libkrunfw kernel config and how the guest mounts cgroups. |
| `module_*` | invalid | Kernel module presence reflects libkrunfw (often built-in); not the image kernel. |
| `module_iscsi_tcp`, `csi_*` | `csi_*` valid (binaries are userspace); `module_iscsi_tcp` invalid | See above. |
| `network_*` (sysctl files) | non-equivalent | Sysctl defaults and available files come from the guest kernel. |
| `nofile` | valid | Userspace limit applied by whatever launches the process. |
| `apparmor`, `seccomp`, `auditd` | non-equivalent | LSM/seccomp/audit support is a kernel build property of libkrunfw. |
| `containerd_systemdcgroup` | non-equivalent | Needs containerd config and systemd as init; a microVM usually has neither as in the image. |
| `runtime_*`, `runtime_compatibility`, `kubernetes_compatibility` | valid | Binary presence/version of userspace packages. |
| `time_sync` | invalid | Guest clock is fed by the hypervisor, not the image's chrony/NTP setup. |
| `provider` | invalid | Can only be `UNKNOWN`/other; smolvm is not a Vagrant provider the image supports. |

### `network/node-network-readiness.sh` (`kube-ready-network/v1`)

| Ids | Verdict | Reason |
|---|---|---|
| `os_id` | valid | Reads `/etc/os-release` of the guest rootfs. |
| `bridge_nf`, the `net.*` sysctl ids, `conntrack`, `conntrack_pressure` | non-equivalent | Kernel modules/sysctls of libkrunfw. |
| `firewall_backend`, `firewall_provider`, `firewall_state`, `firewall_rules`, `egress_chain_removed`, `iptables_backend` | non-equivalent | Tool presence is valid, but the ruleset and nft/legacy backend depend on the guest kernel and a different network path. |
| `mtu_*`, `dual_stack`, `routing`, `ethtool` | invalid | Reflect the hypervisor's virtual NIC and NAT, not the VirtualBox/VMware NIC. |
| `dns_resolver` | non-equivalent | Resolver config is supplied by the microVM runtime. |

### `storage/node-storage-readiness.sh` (`kube-ready-storage/v1`)

| Ids | Verdict | Reason |
|---|---|---|
| `os_id`, `tool_*`, `backend_*`, `lvm_monitor` | valid | Userspace package/tool presence. |
| `mac_backend` | non-equivalent | Depends on guest LSM. |
| `storage_modules`, `mount_propagation`, `quota_capability`, `expansion_test` | invalid | Kernel modules, mount semantics, quota and block expansion are hypervisor/kernel dependent. |
| `root_filesystem`, `capacity`, `capacity_threshold`, `inode_capacity` | invalid | Measure the microVM disk, not the image disk layout. |

### `time/node-time-readiness.sh` (`kube-ready-time/v1`)

| Ids | Verdict | Reason |
|---|---|---|
| `os_id`, `chrony_installed` | valid | Package presence only. |
| `clocksource`, `clock_epoch`, `synchronized`, `timedatectl_sync`, `offset`, `offset_budget`, `sources`, `source_freshness`, `ptp` | invalid | Time comes from the hypervisor clock device and a different clocksource; systemd-timesyncd/chrony behavior is not reproduced. |

### `security/workload-security-check.sh` (`kube-ready-security/v1`)

| Ids | Verdict | Reason |
|---|---|---|
| `os_id`, `runtime_version`, `privileged_workload` | valid | Userspace/OCI workload facts (needs a runtime inside the guest; unverified). |
| `apparmor`, `apparmor_profiles`, `selinux`, `selinux_policy`, `lsm_stack`, `mac_backend` | non-equivalent | LSM stack is the libkrunfw kernel's. |
| `seccomp`, `seccomp_capability`, `seccomp_filter`, `runtime_probe` | non-equivalent | Reflects guest kernel seccomp support; a probe may still be useful as a generic OCI behavior check, labelled by target. |

### `observability/node-diagnostic-profile.sh` (`kube-ready-observability/v1`)

| Ids | Verdict | Reason |
|---|---|---|
| `os_id`, `profile`, `architecture` | valid | Static facts of the guest userspace. |
| `cpu`, `memory`, `disk`, `inode`, `network_interfaces`, `network_io`, `conntrack` | non-equivalent | Sizing and counters describe the microVM, not the image's node. |

### `sandbox/` (`kube-ready-sandbox/v1`)

| Ids | Verdict | Reason |
|---|---|---|
| `runsc` | valid | Binary presence. |
| `containerd_runsc_handler`, `module_*`, `user_namespace`, `pid_limit` | non-equivalent | Handler config is per-node; modules and userns/pid limits come from the guest kernel. |
| `declared`/`supported`/`effective`/`verified`, `missing-runtime-class` negative probe | invalid | These need a Kubernetes cluster with a RuntimeClass; smolvm alone has none. |

### `tools/kube-ready-contracts.sh` aggregate and other reports

| Ids | Verdict | Reason |
|---|---|---|
| `readiness`, `network`, `storage`, `time`, `security`, `observability` reports | per-check, as above | The aggregate status must not be read as one verdict. |
| `license` | valid | Reads package inventory (`dpkg`), pure userspace. |
| `rust_verifier` (`preflight`) | non-equivalent | Mixes valid userspace checks with kernel/init-dependent ones. |
| `rocky`, `nixos` | invalid | Family-specific profiles for different images. |

Not covered by any smolvm run, by construction: boot (`boot_wait`/`boot_command`), bootloader, systemd as PID 1, first-boot identity, Packer provisioner order, the `.box` artifact, and Vagrant provider behavior.

## Prerequisite separation (Phase C input)

Two prerequisite sets must be documented and checked separately:

1. **Host virtualization for smolvm**: KVM on Linux, Hypervisor.framework on macOS, WHP on Windows. These decide whether the microVM can start at all. Details are unverified here.
2. **Kubernetes sandbox runtime prerequisites**: RuntimeClass objects, handler configuration in containerd, runsc/Kata install (#11, #29).

Having one does not imply the other. A passing smolvm run says nothing about RuntimeClass readiness, and a ready RuntimeClass says nothing about smolvm.

## Evidence marking

Every result from this target must carry `execution_context` (see `docs/evidence-contracts.md`): set `KUBE_READY_EXECUTION_TARGET=smolvm` when running the aggregator in the guest. `kernel_release` and `virtualization` are recorded from the guest itself. `full_image_conformance` is `false` for smolvm and `UNKNOWN` otherwise; it is never `true`. `declared_target` is a caller's claim, not detected. The guest kernel provenance (libkrunfw version) is not captured yet; that is Phase B.

## Results must not be read as

- Full Kube Ready Box image conformance, or a release-gating PASS.
- Evidence about the image kernel config, bootloader, systemd boot, kernel modules, time sync, or storage/network behavior of VirtualBox/VMware.
- Proof of RuntimeClass or gVisor/Kata readiness on a Kubernetes node.
- Healthy, when a check is `UNKNOWN`; the project invariant applies unchanged.
- Equivalent to a custom-kernel run: Phase D is not started and equivalence is unproven.
