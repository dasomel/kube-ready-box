# Node network readiness

`network/node-network-readiness.sh` reports effective forwarding, bridge filtering, firewall backend/rules, conntrack capacity, interface MTU, DNS resolver and routing capabilities.

The output uses `kube-ready-network/v1` and deliberately reports unavailable capabilities as `UNKNOWN`.

CNI overlay MTU and kube-proxy mode are workload/cluster-specific; callers should provide selected CNI/Kubernetes profile metadata rather than treating host MTU alone as sufficient compatibility proof.
