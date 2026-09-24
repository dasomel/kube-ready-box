#!/usr/bin/env bash
# Deterministic fixture coverage for #44 T-017 (REQ-005, AC-005):
# sandbox/verify-sandbox-evidence.sh must require Seccomp mode 2
# (RuntimeDefault, effective) and must no longer accept mode 1 (filtering
# only, not the enforced default -- a pod stuck there never actually
# applied RuntimeDefault). Runs the real script against a PATH-stubbed
# `kubectl` fixture that answers every call the script makes, so no cluster
# is required and any real kubectl on the test host never leaks in. Must
# pass on both macOS and Linux.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/sandbox/verify-sandbox-evidence.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# Symlink farm of the real, unconditionally-needed utilities. Deliberately
# excludes kubectl so scenarios control it exactly via a fixture.
essentials_dir="$WORKDIR/essentials"
mkdir -p "$essentials_dir"
for tool in bash cat grep printf python3 mktemp rm; do
  real=$(command -v "$tool" 2>/dev/null || true)
  [ -n "$real" ] && ln -sf "$real" "$essentials_dir/$tool"
done

# write_kubectl_fixture <bindir>
# A fixture kubectl that answers every call verify-sandbox-evidence.sh
# makes: runtimeclass lookup (real class -> handler json, negative class ->
# not found), namespace/pod apply, wait, containerID lookup, in-pod exec
# (Seccomp mode controlled by $FIXTURE_SECCOMP_MODE), the dry-run=server
# negative probe, and namespace delete on the EXIT trap.
write_kubectl_fixture() {
  local bindir=$1
  cat > "$bindir/kubectl" <<'KUBECTL'
#!/usr/bin/env bash
set -euo pipefail

args=("$@")
if [ "${args[0]:-}" = "-n" ]; then
  cmd=("${args[@]:2}")
else
  cmd=("${args[@]}")
fi
sub="${cmd[0]:-}"

case "$sub" in
  get)
    resource="${cmd[1]:-}"
    name="${cmd[2]:-}"
    case "$resource" in
      runtimeclass)
        if [ "$name" = "${RUNTIME_CLASS:-gvisor}" ]; then
          echo '{"handler":"runsc"}'
          exit 0
        fi
        exit 1
        ;;
      pod)
        echo "containerd://deadbeef"
        exit 0
        ;;
    esac
    exit 1
    ;;
  create)
    cat <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: fixture-namespace
YAML
    exit 0
    ;;
  apply)
    cat >/dev/null || true
    for a in "${cmd[@]}"; do
      if [ "$a" = "--dry-run=server" ]; then
        echo 'Error from server (NotFound): no matches for kind "RuntimeClass"' >&2
        exit 1
      fi
    done
    exit 0
    ;;
  wait)
    exit 0
    ;;
  exec)
    printf 'uid=0(root) gid=0(root) groups=0(root)\n'
    printf 'NoNewPrivs:\t1\n'
    printf 'Seccomp:\t%s\n' "${FIXTURE_SECCOMP_MODE:-2}"
    printf 'PID1=/pause\n'
    exit 0
    ;;
  delete)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
KUBECTL
  chmod +x "$bindir/kubectl"
}

# run_scenario <name> <seccomp_mode>
run_scenario() {
  local name=$1 mode=$2
  local bindir="$WORKDIR/$name"
  mkdir -p "$bindir"
  for f in "$essentials_dir"/*; do ln -sf "$f" "$bindir/$(basename "$f")"; done
  write_kubectl_fixture "$bindir"
  local out="$WORKDIR/$name-evidence.json"
  set +e
  PATH="$bindir" RUNTIME_CLASS=gvisor NAMESPACE="kube-ready-sandbox-$name" \
    OUTPUT="$out" FIXTURE_SECCOMP_MODE="$mode" \
    bash "$SCRIPT" >"$WORKDIR/$name.stdout" 2>"$WORKDIR/$name.stderr"
  local rc=$?
  set -e
  python3 -m json.tool "$out" >/dev/null || {
    echo "::error::$name did not produce parseable evidence JSON" >&2
    cat "$WORKDIR/$name.stderr" >&2
    exit 1
  }
  printf '%s %s\n' "$out" "$rc"
}

assert_field() {
  local out=$1 path=$2 expected=$3
  python3 - "$out" "$path" "$expected" <<'PY'
import json, sys
path_file, field_path, expected = sys.argv[1:]
doc = json.load(open(path_file, encoding="utf-8"))
node = doc
for part in field_path.split("."):
    node = node[part]
if node != expected:
    print(f"::error::{path_file}: {field_path!r} expected {expected!r}, got {node!r}")
    raise SystemExit(1)
PY
}

# --- allow: Seccomp mode 2 (RuntimeDefault, effective) -> PASS, exit 0 ---
read -r allow_out allow_rc < <(run_scenario mode2-allow 2)
assert_field "$allow_out" checks.seccompNoNewPrivs PASS
assert_field "$allow_out" lifecycle.verified PASS
assert_field "$allow_out" status PASS
[ "$allow_rc" -eq 0 ] || { echo "::error::expected exit 0 for Seccomp mode 2, got $allow_rc" >&2; exit 1; }

# --- deny: Seccomp mode 1 (filtering, not the enforced default) -> not PASS ---
read -r deny_out deny_rc < <(run_scenario mode1-deny 1)
assert_field "$deny_out" checks.seccompNoNewPrivs FAIL
assert_field "$deny_out" lifecycle.verified FAIL
assert_field "$deny_out" status FAIL
[ "$deny_rc" -ne 0 ] || { echo "::error::expected non-zero exit for a pod stuck at Seccomp mode 1" >&2; exit 1; }

echo "sandbox-seccomp-mode-test.sh: all scenarios passed"
