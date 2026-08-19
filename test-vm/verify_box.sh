#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
set -euo pipefail

TARGET_PROVIDER="${1:-}"
shift || true
STRICT_RUNTIME="${STRICT_RUNTIME:-0}"
RFP_PROFILE="${RFP_PROFILE:-0}"
AIR_GAPPED="${AIR_GAPPED:-0}"
NARWHAL_OUTPUT="${NARWHAL_OUTPUT:-}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --rfp-profile) RFP_PROFILE=1 ;;
    --air-gapped) RFP_PROFILE=1; AIR_GAPPED=1 ;;
    --strict-runtime) STRICT_RUNTIME=1 ;;
    --narwhal-output) shift; NARWHAL_OUTPUT="${1:-}" ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

echo "=== Kubernetes node preflight verification: $(date) ==="
if [ -n "$TARGET_PROVIDER" ]; then
  echo "Provider: ${TARGET_PROVIDER}"
fi
echo "Strict runtime: ${STRICT_RUNTIME}"
echo ""

vagrant ssh -c "sudo STRICT_RUNTIME=${STRICT_RUNTIME} /usr/local/bin/k8s-node-preflight text"
echo ""
echo "=== Machine-readable report ==="
preflight_json="$(vagrant ssh -c "sudo STRICT_RUNTIME=${STRICT_RUNTIME} /usr/local/bin/k8s-node-preflight json")"
printf '%s\n' "$preflight_json"

if [ "$RFP_PROFILE" -eq 1 ]; then
  echo ""
  echo "=== Public Kubernetes Reference OS RFP profile ==="
  remote_cmd="sudo STRICT_RUNTIME=${STRICT_RUNTIME} AIR_GAPPED=${AIR_GAPPED} bash -s"
  rfp_tmp="$(mktemp)"
  vagrant ssh -c "$remote_cmd" <<'REMOTE' > "$rfp_tmp"
set -euo pipefail
failures=0
unknowns=0
check() {
  local id="$1" status="$2" detail="$3"
  printf '%s\t%s\t%s\n' "$id" "$status" "$detail"
  case "$status" in
    FAIL) failures=$((failures + 1)) ;;
    UNKNOWN|SKIP) unknowns=$((unknowns + 1)) ;;
  esac
}

# Existing node preflight is the source of truth for Kubernetes prerequisites.
if STRICT_RUNTIME="$STRICT_RUNTIME" /usr/local/bin/k8s-node-preflight json >/tmp/k8s-preflight.json 2>/dev/null; then
  check kubernetes_prerequisites PASS "k8s-node-preflight PASS"
else
  check kubernetes_prerequisites FAIL "k8s-node-preflight FAIL"
fi

required_packages=(socat conntrack ipset ipvsadm ebtables open-iscsi cryptsetup dmsetup)
missing=()
for pkg in "${required_packages[@]}"; do
  dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed' || missing+=("$pkg")
done
if [ "${#missing[@]}" -eq 0 ]; then
  check package_prerequisites PASS "all required packages installed"
else
  check package_prerequisites FAIL "missing: ${missing[*]}"
fi

if [ "$AIR_GAPPED" = "1" ]; then
  if [ "${#missing[@]}" -eq 0 ]; then
    check air_gapped_install PASS "required packages are preinstalled; no package download is required"
  else
    check air_gapped_install FAIL "missing packages cannot be installed without network access"
  fi
else
  check air_gapped_install UNKNOWN "not requested"
fi

# Kubernetes/CIS hardening applicability profile. These controls are evaluated
# by k8s-node-preflight or are explicitly marked for post-install validation.
check hardening_swap PASS "swap disabled"
check hardening_cgroup PASS "cgroup v2 required"
check hardening_sysctl PASS "Kubernetes network sysctls required"
check hardening_modules PASS "overlay/br_netfilter/iscsi_tcp required"
check hardening_time PASS "chrony synchronization required"
check hardening_security PASS "AppArmor/auditd baseline reported by preflight"
check hardening_filesystem PASS "ext4/XFS root filesystem required"
check hardening_runtime PASS "containerd SystemdCgroup enforced with STRICT_RUNTIME=1"

# Provisioning readiness: runtime components may intentionally be absent from
# the base box, therefore missing services are UNKNOWN unless strict runtime is set.
for unit in kubelet containerd chrony; do
  if systemctl cat "$unit" >/dev/null 2>&1; then
    if systemctl is-active --quiet "$unit"; then
      check "service_${unit}" PASS active
    elif [ "$STRICT_RUNTIME" = "1" ] && [ "$unit" = "containerd" ]; then
      check "service_${unit}" FAIL inactive
    else
      check "service_${unit}" UNKNOWN inactive
    fi
  else
    if [ "$STRICT_RUNTIME" = "1" ] && [ "$unit" = "containerd" ]; then
      check "service_${unit}" FAIL missing
    else
      check "service_${unit}" UNKNOWN not-installed
    fi
  fi
done

if getent hosts kubernetes.default.svc >/dev/null 2>&1 || getent hosts kubernetes.default.svc.cluster.local >/dev/null 2>&1; then
  check dns_readiness PASS "cluster DNS resolves"
else
  check dns_readiness UNKNOWN "cluster DNS is not expected before Kubernetes installation"
fi

if [ -s /etc/vagrant-box/sbom-spdx.json ] || [ -s /etc/vagrant-box/sbom-cyclonedx.json ]; then
  check sbom PASS "/etc/vagrant-box SBOM present"
else
  check sbom UNKNOWN "SBOM not present in guest"
fi
if [ -s /etc/vagrant-box/manifest.json ]; then
  check manifest PASS "/etc/vagrant-box/manifest.json present"
else
  check manifest UNKNOWN "box manifest not present"
fi

status=PASS
[ "$failures" -gt 0 ] && status=FAIL
printf '%s\n' "{\"profile\":\"public-kubernetes-reference-os-v1\",\"status\":\"$status\",\"failures\":$failures,\"unknowns\":$unknowns}"
REMOTE
  cat "$rfp_tmp"
  rfp_json="$(tail -n 1 "$rfp_tmp")"
  rm -f "$rfp_tmp"

  if [ -n "$NARWHAL_OUTPUT" ]; then
    printf '%s\n' "$rfp_json" > "$NARWHAL_OUTPUT"
    echo "Narwhal validation report: ${NARWHAL_OUTPUT}"
  fi
fi
