#!/usr/bin/env bash
# Deterministic coverage for #44 T-013/T-014: native LSM selection follows
# ID then ID_LIKE, and seccomp_filter distinguishes available, absent and
# unobservable kernel support without relying on the host running the test.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# Repoint only the OS and proc evidence paths in a temporary copy of the real
# validator. All classification and status logic remains the production code.
sed \
  -e "s|/etc/os-release|$WORKDIR/os-release|g" \
  -e "s|/proc/self/status|$WORKDIR/proc-status|g" \
  -e "s|/proc/sys/kernel/seccomp/actions_avail|$WORKDIR/actions-avail|g" \
  -e "s|/proc/version|$WORKDIR/proc-version|g" \
  "$ROOT/security/workload-security-check.sh" > "$WORKDIR/workload-security-check.sh"
chmod +x "$WORKDIR/workload-security-check.sh"

mkdir -p "$WORKDIR/bin"
cat > "$WORKDIR/bin/getenforce" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "${FIXTURE_SELINUX_STATE:-Enforcing}"
SHIM
chmod +x "$WORKDIR/bin/getenforce"

write_os_release() {
  printf 'ID="%s"\nID_LIKE="%s"\n' "$1" "$2" > "$WORKDIR/os-release"
}

write_proc_status() {
  printf 'Name:\tbash\nSeccomp:\t2\n%s' "$1" > "$WORKDIR/proc-status"
}

run_case() {
  local name=$1 id=$2 id_like=$3 status_extra=$4 actions=$5 known_kernel=$6 selinux_state=$7
  local actions_present=${8:-yes}
  local output="$WORKDIR/$name.json" rc
  write_os_release "$id" "$id_like"
  write_proc_status "$status_extra"
  printf '%s\n' "$actions" > "$WORKDIR/actions-avail"
  if [ "$known_kernel" = yes ]; then
    printf 'Linux version fixture\n' > "$WORKDIR/proc-version"
    [ "$actions_present" = yes ] || rm -f "$WORKDIR/actions-avail"
  else
    rm -f "$WORKDIR/proc-version" "$WORKDIR/actions-avail"
  fi
  set +e
  PATH="$WORKDIR/bin:$PATH" FIXTURE_SELINUX_STATE="$selinux_state" \
    bash "$WORKDIR/workload-security-check.sh" > "$output" 2> "$WORKDIR/$name.stderr"
  rc=$?
  set -e
  python3 -m json.tool "$output" >/dev/null || {
    echo "::error::$name produced invalid JSON" >&2
    cat "$WORKDIR/$name.stderr" >&2
    exit 1
  }
  printf '%s\n' "$rc" > "$output.exit"
  printf '%s %s\n' "$output" "$rc"
}

assert_check() {
  local output=$1 check_id=$2 expected_status=$3 expected_detail=$4 expected_overall=$5 expected_rc=$6
  python3 - "$output" "$check_id" "$expected_status" "$expected_detail" "$expected_overall" "$expected_rc" <<'PY'
import json, sys
path, check_id, expected_status, expected_detail, expected_overall, expected_rc = sys.argv[1:]
doc = json.load(open(path, encoding="utf-8"))
matches = [check for check in doc.get("checks", []) if check.get("id") == check_id]
if len(matches) != 1:
    raise SystemExit(f"{path}: expected one {check_id}, got {len(matches)}")
actual = matches[0]
if actual.get("status") != expected_status or actual.get("detail") != expected_detail:
    raise SystemExit(f"{path}: expected {check_id}={expected_status}/{expected_detail!r}, got {actual}")
if doc.get("status") != expected_overall:
    raise SystemExit(f"{path}: expected overall {expected_overall}, got {doc.get('status')}")
actual_rc = open(path + ".exit", encoding="utf-8").read().strip()
if actual_rc != expected_rc:
    raise SystemExit(f"{path}: expected process exit {expected_rc}, got {actual_rc}")
PY
}

actions='kill_process kill_thread trap errno user_notif trace log allow'
status_field=$'Seccomp_filters:\t0\n'

# ID has precedence; all native families map to the expected LSM backend.
for id in ubuntu debian nixos rocky rhel alma almalinux fedora centos; do
  result=$(run_case "family-$id" "$id" '' "$status_field" "$actions" yes Enforcing)
  read -r output _ <<< "$result"
  case "$id" in
    ubuntu|debian|nixos) assert_check "$output" mac_backend PASS AppArmor PASS 0 ;;
    *) assert_check "$output" mac_backend PASS SELinux PASS 0 ;;
  esac
  assert_check "$output" seccomp_filter PASS Seccomp_filters=0 PASS 0
done

# Unknown IDs fall back to the first recognized ID_LIKE token.
result=$(run_case family-like-debian custom debian "$status_field" "$actions" yes Enforcing)
read -r output _ <<< "$result"
assert_check "$output" mac_backend PASS AppArmor PASS 0
result=$(run_case family-like-rhel custom 'rhel fedora' "$status_field" "$actions" yes Enforcing)
read -r output _ <<< "$result"
assert_check "$output" mac_backend PASS SELinux PASS 0
for os_like in alma almalinux fedora centos; do
  result=$(run_case "family-like-$os_like" custom "$os_like" "$status_field" "$actions" yes Enforcing)
  read -r output _ <<< "$result"
  assert_check "$output" mac_backend PASS SELinux PASS 0
done
result=$(run_case family-like-order-apparmor custom 'debian fedora' "$status_field" "$actions" yes Enforcing)
read -r output _ <<< "$result"
assert_check "$output" mac_backend PASS AppArmor PASS 0
result=$(run_case family-like-order-selinux custom 'fedora debian' "$status_field" "$actions" yes Enforcing)
read -r output _ <<< "$result"
assert_check "$output" mac_backend PASS SELinux PASS 0
result=$(run_case family-id-precedes-like debian rhel "$status_field" "$actions" yes Enforcing)
read -r output _ <<< "$result"
assert_check "$output" mac_backend PASS AppArmor PASS 0
result=$(run_case family-unknown unknown '' "$status_field" "$actions" yes Enforcing)
read -r output _ <<< "$result"
assert_check "$output" mac_backend UNKNOWN unknown PASS 0

# A disabled SELinux mode on an ID_LIKE-classified native distro is not hidden.
result=$(run_case family-alma-disabled custom almalinux "$status_field" "$actions" yes Disabled)
read -r output _ <<< "$result"
assert_check "$output" selinux FAIL Disabled FAIL 1

# Older kernels can prove support from action names when the status field is absent.
result=$(run_case filter-actions unknown '' '' "$actions" yes Enforcing)
read -r output _ <<< "$result"
assert_check "$output" seccomp_filter PASS "actions_avail=$actions" PASS 0

# Known Linux without either proof fails; an environment without proc evidence stays UNKNOWN.
result=$(run_case filter-missing unknown '' '' 'kill_thread trap allow' yes Enforcing)
read -r output _ <<< "$result"
assert_check "$output" seccomp_filter FAIL filter-actions-unavailable FAIL 1
result=$(run_case filter-mode-unavailable unknown '' '' '' yes Enforcing no)
read -r output _ <<< "$result"
assert_check "$output" seccomp_filter FAIL filter-mode-unavailable FAIL 1
result=$(run_case filter-unobservable unknown '' '' '' no Enforcing)
read -r output _ <<< "$result"
assert_check "$output" seccomp_filter UNKNOWN kernel-unavailable PASS 0

echo "workload-security-classification-test.sh: all scenarios passed"
