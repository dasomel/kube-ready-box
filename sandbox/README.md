# Sandbox-ready node profile

`kube-ready-box` remains a node foundation. It does **not** execute user code itself.

Profiles:

- `standard`: existing containerd/runc behavior; no sandbox runtime required.
- `sandbox`: runsc/gVisor runtime handler plus Kubernetes `RuntimeClass`.
- `hardened-sandbox`: sandbox profile plus node taint/label, restrictive seccomp/capability baseline and network-policy requirements.

## Runtime contract

The image may contain the configuration directory, but `runsc` is an optional artifact. A sandbox image must report `runsc` version, digest, provenance and SBOM evidence before it is advertised as sandbox-ready.

```bash
sudo ./sandbox/preflight-sandbox.sh
```

A missing runsc binary is `UNKNOWN` for the standard profile and `FAIL` for an explicitly requested sandbox profile. Unsupported provider/architecture combinations are never silently treated as supported.

## Containerd

Configure the runtime handler in `/etc/containerd/config.toml` only when the runsc artifact is present and verified. Example:

```toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]
  runtime_type = "io.containerd.runsc.v1"
```

Then apply the Kubernetes `RuntimeClass` in `runtimeclass.yaml`.

## Node scheduling

Recommended sandbox nodes:

```yaml
nodeSelector:
  kube-ready-box/sandbox: "true"
tolerations:
- key: kube-ready-box/sandbox
  operator: Exists
  effect: NoSchedule
```

The controller/platform layer is responsible for choosing the RuntimeClass and applying NetworkPolicy. The box only provides the node capability and evidence.
