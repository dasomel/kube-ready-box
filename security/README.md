# Workload security contract

`security/workload-security-check.sh` provides distro-neutral host/workload security evidence.

The contract distinguishes:

`declared → supported → loaded → effective → verified`

Ubuntu uses AppArmor and Rocky uses SELinux. A node-only check cannot prove a workload's effective profile, so actual pod/container verification must be performed in the Kubernetes test environment and linked to this evidence. Privileged/host namespace use is always an explicit risk signal.

Unsupported MAC/seccomp capabilities are `UNKNOWN`, not healthy.
