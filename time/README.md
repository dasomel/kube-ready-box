# Node time readiness

`time/node-time-readiness.sh` distinguishes chrony installation from actual synchronization, reports sources/clocksource/optional PTP and emits `kube-ready-time/v1` evidence.

A clock is not considered healthy merely because a config file exists. Time-source loss is a failure when synchronization was expected; unsupported PTP is `UNKNOWN` rather than failure. Kubernetes/etcd/PKI consumers can apply their own configured offset budget to the evidence.
