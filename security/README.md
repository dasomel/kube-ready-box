# Workload security contract

`security/workload-security-check.sh` provides distro-neutral host/workload security evidence.

The contract distinguishes:

`declared → supported → loaded → effective → verified`

Ubuntu, Debian and NixOS use AppArmor; Rocky, RHEL, Alma, Fedora and CentOS use SELinux. The validator selects the native family from `/etc/os-release` `ID`, then the ordered `ID_LIKE` tokens. A node-only check cannot prove a workload's effective profile, so actual pod/container verification must be performed in the Kubernetes test environment and linked to this evidence. Privileged/host namespace use is always an explicit risk signal.

Unavailable capability evidence is `UNKNOWN`; missing required native LSM or seccomp support is not reported healthy.

`seccomp_filter` (#44 T-014) reports filter-mode support from the `Seccomp_filters`
field in `/proc/self/status` or the `errno` and `kill_process` actions in
`/proc/sys/kernel/seccomp/actions_avail`. A known Linux kernel without either signal
reports `FAIL`; effective pod-level `RuntimeDefault` remains a separate check.

`lsm_stack` (#44 T-012) additionally reports the kernel's active LSM stack from
`/sys/kernel/security/lsm` (e.g. `apparmor`, or `lockdown,capability,landlock,yama,apparmor,integrity`).
It is additive-only and never `FAIL`s: readable/non-empty -> `PASS <raw list>`; securityfs not
mounted -> `UNKNOWN securityfs-absent`; present but unreadable -> `UNKNOWN permission-denied`. See
`docs/evidence-contracts.md` for the full detail vocabulary.

Effective `Seccomp: RuntimeDefault` (mode `2`) at the pod level is verified by
`sandbox/verify-sandbox-evidence.sh` (#44 T-017); a pod stuck at mode `1` no longer passes. See
`docs/evidence-contracts.md`.
