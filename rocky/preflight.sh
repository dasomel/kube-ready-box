#!/usr/bin/env bash
set -euo pipefail
SCHEMA=kube-ready-readiness/v1
checks=(); failures=0; unknowns=0
add(){ local id=$1 st=$2 d=$3; checks+=("{\"id\":\"$id\",\"status\":\"$st\",\"detail\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$d")}"); case "$st" in FAIL) failures=$((failures+1));; UNKNOWN) unknowns=$((unknowns+1));; esac; }

[ -r /etc/os-release ] && . /etc/os-release
ID="${ID:-}"; VERSION_ID="${VERSION_ID:-}"
[[ "$ID" = rocky ]] && add os PASS "${PRETTY_NAME:-unknown}" || add os FAIL "not Rocky Linux"
add architecture PASS "$(uname -m)"
selinux=$(getenforce 2>/dev/null || echo unavailable); case "$selinux" in Enforcing) add selinux PASS "$selinux";; Permissive|Disabled) add selinux FAIL "$selinux";; *) add selinux UNKNOWN "$selinux";; esac
if [ -r /etc/selinux/config ]; then
  cfg_selinux=$(grep -E '^SELINUX=' /etc/selinux/config 2>/dev/null | cut -d= -f2 || true)
  case "$cfg_selinux" in
    enforcing)
      case "$selinux" in
        Enforcing) add selinux_config_consistency PASS "config=$cfg_selinux runtime=$selinux" ;;
        Permissive|Disabled) add selinux_config_consistency FAIL "config=$cfg_selinux runtime=$selinux" ;;
        *) add selinux_config_consistency UNKNOWN "config=$cfg_selinux runtime=$selinux" ;;
      esac
      ;;
    permissive|disabled)
      case "$selinux" in
        Enforcing) add selinux_config_consistency FAIL "config=$cfg_selinux runtime=$selinux (will not persist enforcement after reboot)" ;;
        Permissive|Disabled) add selinux_config_consistency PASS "config=$cfg_selinux runtime=$selinux" ;;
        *) add selinux_config_consistency UNKNOWN "config=$cfg_selinux runtime=$selinux" ;;
      esac
      ;;
    *) add selinux_config_consistency UNKNOWN "config=${cfg_selinux:-unset} runtime=$selinux" ;;
  esac
else
  add selinux_config_consistency UNKNOWN "config file missing"
fi
command -v firewall-cmd >/dev/null && add firewalld PASS installed || add firewalld UNKNOWN unavailable
if command -v iptables >/dev/null 2>&1; then
  # --display lists the whole alternatives registry (both iptables-legacy and
  # iptables-nft entries always appear), so a substring match on it reports
  # the wrong backend whenever both are registered. --query's "Value:" line
  # names only the currently active link.
  ipt_active=$(update-alternatives --query iptables 2>/dev/null | awk '/^Value:/{print $2; exit}') || true
  if [ -z "$ipt_active" ]; then
    ipt_active=$(readlink -f "$(command -v iptables)" 2>/dev/null) || true
  fi
  case "$ipt_active" in
    *legacy*) add iptables_backend PASS legacy ;;
    *nft*) add iptables_backend PASS nft ;;
    *) add iptables_backend UNKNOWN "${ipt_active:-indeterminate}" ;;
  esac
else
  add iptables_backend UNKNOWN "iptables not installed"
fi
systemctl is-active --quiet NetworkManager && add networkmanager PASS active || add networkmanager UNKNOWN inactive
stat -fc %T /sys/fs/cgroup 2>/dev/null | grep -q cgroup2fs && add cgroup_v2 PASS enabled || add cgroup_v2 FAIL missing
swapon --show --noheadings 2>/dev/null | grep -q . && add swap FAIL enabled || add swap PASS disabled
for m in overlay br_netfilter; do grep -q "^$m " /proc/modules 2>/dev/null && add module_$m PASS loaded || add module_$m FAIL not-loaded; done
grep -q '^nf_conntrack ' /proc/modules 2>/dev/null && add module_conntrack PASS loaded || add module_conntrack FAIL not-loaded
grep -q '^dm_mod ' /proc/modules 2>/dev/null && add module_dm_mod PASS loaded || add module_dm_mod FAIL not-loaded
for p in /proc/sys/net/ipv4/ip_forward /proc/sys/net/bridge/bridge-nf-call-iptables; do [ -r "$p" ] && [ "$(cat "$p")" = 1 ] && add "sysctl_$(basename "$p")" PASS 1 || add "sysctl_$(basename "$p")" FAIL missing-or-zero; done
mountpoint -q /sys/fs/bpf 2>/dev/null && add bpffs PASS mounted || add bpffs UNKNOWN not-mounted
if systemctl cat containerd >/dev/null 2>&1; then grep -Rqs 'SystemdCgroup[[:space:]]*=[[:space:]]*true' /etc/containerd 2>/dev/null && add containerd_systemdcgroup PASS enabled || add containerd_systemdcgroup FAIL disabled; else add containerd_systemdcgroup UNKNOWN not-installed; fi
command -v chronyc >/dev/null && add chrony PASS installed || add chrony UNKNOWN missing
for x in iscsiadm cryptsetup dmsetup; do command -v "$x" >/dev/null && add csi_$x PASS present || add csi_$x UNKNOWN missing; done
systemctl is-active --quiet iscsid 2>/dev/null && add iscsid_active PASS active || add iscsid_active UNKNOWN inactive
fs=$(findmnt -n -o FSTYPE / 2>/dev/null || echo unknown); case "$fs" in xfs|ext4) add filesystem PASS "$fs";; *) add filesystem UNKNOWN "$fs";; esac

if [[ "$VERSION_ID" == 10* ]]; then
  if uname -m | grep -Eq 'x86_64|amd64'; then
    flags=$(grep -m1 '^flags' /proc/cpuinfo 2>/dev/null || true)
    for f in avx avx2 bmi1 bmi2 f16c; do echo "$flags" | grep -qw "$f" || { add rocky10_x86_64_v3 FAIL "missing $f"; break; }; done
    [ "${#checks[@]}" -gt 0 ] && ! printf '%s\n' "${checks[@]}" | grep -q 'rocky10_x86_64_v3' && add rocky10_x86_64_v3 PASS cpu-flags
  else add rocky10_x86_64_v3 UNKNOWN "non-x86_64 architecture"; fi
else add rocky10_x86_64_v3 UNKNOWN "not Rocky 10"; fi

status=PASS; [ "$failures" -gt 0 ] && status=FAIL
printf '{"schema":"%s","kind":"rocky-node-readiness","status":"%s","os":"%s","version":"%s","architecture":"%s","failures":%d,"unknowns":%d,"checks":[%s]}\n' "$SCHEMA" "$status" "$ID" "$VERSION_ID" "$(uname -m)" "$failures" "$unknowns" "$(IFS=,; echo "${checks[*]}")"
[ "$status" = PASS ]
