# Node time readiness

`time/node-time-readiness.sh` distinguishes chrony installation from actual synchronization, reports sources/clocksource/optional PTP and emits `kube-ready-time/v1` evidence.

A clock is not considered healthy merely because a config file exists. Time-source loss is a failure when synchronization was expected; unsupported PTP is `UNKNOWN` rather than failure. Kubernetes/etcd/PKI consumers can apply their own configured offset budget to the evidence.

## Certificate clock sanity

`cert_clock_sanity` fails when the node clock is outside a certificate's validity window (`now < NotBefore` is `not-yet-valid`, `now > NotAfter` is `expired`), which breaks TLS to the API server/kubelet. It uses `openssl` over `TIME_READINESS_CERT_PATHS` (space-separated globs, default `/etc/kubernetes/pki/*.crt /var/lib/kubelet/pki/*.crt`) and `TIME_READINESS_NOW` (epoch seconds, default current time; for fixtures). Precedence: any expired/not-yet-valid certificate gives `FAIL` (wins over everything else); otherwise no matching certificate, missing `openssl`, or any unparseable file (even alongside valid ones, detail `unparseable=X;valid=Y`) gives `UNKNOWN`; `PASS` only when every matched certificate parsed and is valid. `UNKNOWN` never fails the overall status by itself. Only the first certificate in each file is inspected. There is no expiry-soon warning level in this contract.
