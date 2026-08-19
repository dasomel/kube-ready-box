# Kubernetes Node Readiness Attestation

`tools/node-readiness-attest.sh` produces `kube-ready-readiness/v1` evidence for a booted box. It is intentionally independent from Kubernetes installation and can run before kubeadm/Kubespray/Narwhal provisioning.

## Checks

The baseline covers cgroup v2, swap, required kernel modules, Kubernetes sysctls, bpffs, containerd SystemdCgroup, runc/ctr, CSI prerequisites, chrony/time sync, AppArmor/seccomp/auditd, conntrack/network state, nofile, root filesystem, architecture and provider.

`PASS`, `FAIL`, and `UNKNOWN` are deliberately distinct. An unavailable optional capability is never represented as healthy. Set `STRICT_READINESS=1` to fail on unknown checks as well as failures.

## Immutable evidence

After generating readiness evidence:

```bash
tools/node-readiness-manifest.sh
```

The manifest binds the box `info.json` digest and readiness report digest to the validator schema/version.

## Drift

Capture a fresh report after provisioning/customization and compare it with the baseline:

```bash
tools/node-readiness-drift.sh
```

A changed effective security/runtime/network/storage state is reported as `DRIFT`.

## Offline reproducibility

The validator uses local `/proc`, `/sys`, systemd and installed command state only. It does not install packages or query online services. Export the JSON report and immutable manifest together with the box release evidence to reproduce the decision offline.

## Compatibility selection

`KUBERNETES_VERSION` and `CONTAINERD_VERSION` can be supplied to record the selected compatibility target. The validator intentionally reports the target as `UNKNOWN` until a concrete installed version matrix is verified; it does not guess compatibility.
