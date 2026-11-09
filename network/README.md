# Node network readiness

`network/node-network-readiness.sh` reports effective forwarding, bridge filtering, firewall backend/rules, conntrack capacity, interface MTU, DNS resolver and routing capabilities.

The output uses `kube-ready-network/v1` and deliberately reports unavailable capabilities as `UNKNOWN`.

CNI overlay MTU and kube-proxy mode are workload/cluster-specific; callers should provide selected CNI/Kubernetes profile metadata rather than treating host MTU alone as sufficient compatibility proof.

## Operator-declared overlay MTU (`cni_overlay_mtu`)

Inputs: `CNI_OVERLAY_MTU` (the pod/overlay MTU the CNI is configured with) and optional `CNI_OVERLAY_OVERHEAD` (encapsulation bytes, default `50` = VXLAN over IPv4; Geneve is 50 without options, IPIP 20, WireGuard 60 -- an assumption, set it for your CNI). The check compares `overlay + overhead` with the MTU of the default-route interface (IPv4 default first, falling back to the IPv6 default on IPv6-only hosts).

- fits -> `PASS`; does not fit -> `FAIL` (detail `overlay=.. overhead=.. host=.. iface=.. family=ipv4|ipv6`)
- `CNI_OVERLAY_MTU` unset -> `UNKNOWN not-requested`; non-numeric -> `UNKNOWN invalid-input`
- no default route / no `ip` -> `UNKNOWN default-route-interface-unavailable`; unreadable interface MTU -> `UNKNOWN host-mtu-unreadable`

## kube-proxy backend capability (`kube_proxy_nftables`, `kube_proxy_ipvs`)

Capability only, never `FAIL` and never a hard requirement; which backend is configured is not inspected.

- `kube_proxy_nftables`: `nft` present and kernel `nf_tables` loaded -> `PASS`; otherwise `UNKNOWN` (`nft-absent`, `nf_tables-not-detected`, `kernel-modules-unreadable`).
- `kube_proxy_ipvs`: `ip_vs` loaded (`/proc/net/ip_vs` or `/proc/modules`) -> `PASS ip_vs-loaded ipvsadm-present|ipvsadm-absent`; otherwise `UNKNOWN` (`ip_vs-not-loaded ..`, `kernel-modules-unreadable`). A built-in or not-yet-loaded module is reported as `UNKNOWN`, not as unsupported.

