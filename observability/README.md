# Optional node observability profile

`observability/node-diagnostic-profile.sh` is intentionally optional and bounded. It collects normalized CPU/memory/disk/network/capability evidence without enabling continuous agents, packet capture or eBPF tracing by default.

Safety properties:

- maximum collection duration: 300 seconds
- bounded evidence size
- raw command output excluded by default
- tcpdump/bpftrace/audit capabilities are reported rather than automatically invoked
- unsupported tools are `UNKNOWN`, not zero
- output schema: `kube-ready-observability/v1`

The profile can be connected to #13 readiness and downstream Narwhal/KubeMetal evidence bundles without parsing distro-specific command output.
