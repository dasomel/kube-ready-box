#!/usr/bin/env bash
# Deterministic fixture coverage for #44 T-015 (REQ-007, AC-006): the static
# host-mutation guard must pass the real tree, must fail per line/form (not
# per file) on an injected mutation naming file:line, must never flag a
# read-only invocation of the same tools, and an allowlisted file must still
# fail on a mutating form outside its specifically-approved lines.
#
# GUARD_ROOT points the guard at a plain (non-git) fixture directory -- the
# guard falls back to a directory walk when `git ls-files` finds nothing,
# specifically so this test does not need to `git init` a throwaway tree.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD="$ROOT/tools/host-mutation-guard.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# 1. The real, current tree must pass as-is (AC-006 allow).
bash "$GUARD" >/dev/null

# --- fixture tree for the injected-violation scenarios ---
FIXTURE="$WORKDIR/fixture"
mkdir -p "$FIXTURE/packer/scripts"
cp "$ROOT/packer/scripts/rocky-tuning.sh" "$FIXTURE/packer/scripts/rocky-tuning.sh"

run_guard() {
  set +e
  GUARD_ROOT="$FIXTURE" bash "$GUARD" >"$WORKDIR/out.log" 2>&1
  rc=$?
  set -e
  return "$rc"
}

# 2. The untouched fixture (just a copy of an already-allowlisted file) must
# still pass -- proves the allowlist itself, not just an empty tree, is fine.
if ! run_guard; then
  echo "FAIL: unmodified fixture tree did not pass" >&2
  cat "$WORKDIR/out.log" >&2
  exit 1
fi

# 3. Deny: `ufw enable` injected into a brand-new, non-allowlisted file must
# fail and name that file:line.
cat > "$FIXTURE/some-other-script.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ufw enable
EOF
if run_guard; then
  echo "FAIL: injected 'ufw enable' in a non-allowlisted file was not detected" >&2
  exit 1
fi
grep -q "some-other-script.sh:3:.*ufw" "$WORKDIR/out.log" || {
  echo "FAIL: violation report does not name some-other-script.sh:3" >&2
  cat "$WORKDIR/out.log" >&2
  exit 1
}
rm -f "$FIXTURE/some-other-script.sh"

# 4. Deny: `setenforce 0` added to an already-allowlisted file, outside its
# documented `setenforce 1` enforcing-preservation line, must still fail --
# the allowlist is per line/form, not per file.
printf 'setenforce 0\n' >> "$FIXTURE/packer/scripts/rocky-tuning.sh"
if run_guard; then
  echo "FAIL: 'setenforce 0' added to an allowlisted file was not detected" >&2
  exit 1
fi
grep -q "packer/scripts/rocky-tuning.sh:.*setenforce" "$WORKDIR/out.log" || {
  echo "FAIL: violation report does not name rocky-tuning.sh's injected line" >&2
  cat "$WORKDIR/out.log" >&2
  exit 1
}
# restore the allowlisted file to its original, passing form
cp "$ROOT/packer/scripts/rocky-tuning.sh" "$FIXTURE/packer/scripts/rocky-tuning.sh"
if ! run_guard; then
  echo "FAIL: fixture did not pass again after removing the injected line" >&2
  cat "$WORKDIR/out.log" >&2
  exit 1
fi

# 5. Allow: read-only invocations of every covered tool must pass anywhere,
# allowlisted or not -- kube-ready-box's own validators rely on this.
cat > "$FIXTURE/readonly-check.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
command -v nft >/dev/null 2>&1 && nft list ruleset
command -v ufw >/dev/null 2>&1 && ufw status
command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state
command -v getenforce >/dev/null 2>&1 && getenforce
command -v aa-status >/dev/null 2>&1 && aa-status
command -v iptables >/dev/null 2>&1 && iptables -S KUBE_READY_EGRESS
command -v iptables >/dev/null 2>&1 && iptables -L
EOF
if ! run_guard; then
  echo "FAIL: read-only firewall/LSM invocations were flagged" >&2
  cat "$WORKDIR/out.log" >&2
  exit 1
fi
rm -f "$FIXTURE/readonly-check.sh"

# 6. Deny: `sudo setenforce 0` in a non-allowlisted file must still be caught
# -- a sudo prefix must never let a mutation slip through.
cat > "$FIXTURE/sudo-mutation.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sudo setenforce 0
EOF
if run_guard; then
  echo "FAIL: 'sudo setenforce 0' was not detected" >&2
  exit 1
fi
grep -q "sudo-mutation.sh:3:.*setenforce" "$WORKDIR/out.log" || {
  echo "FAIL: violation report does not name sudo-mutation.sh:3" >&2
  cat "$WORKDIR/out.log" >&2
  exit 1
}
rm -f "$FIXTURE/sudo-mutation.sh"

# 7. Deny: an absolute-path invocation (`/usr/sbin/iptables -F`) in a
# non-allowlisted file must still be caught.
cat > "$FIXTURE/abspath-mutation.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
/usr/sbin/iptables -F
EOF
if run_guard; then
  echo "FAIL: '/usr/sbin/iptables -F' was not detected" >&2
  exit 1
fi
grep -q "abspath-mutation.sh:3:.*iptables" "$WORKDIR/out.log" || {
  echo "FAIL: violation report does not name abspath-mutation.sh:3" >&2
  cat "$WORKDIR/out.log" >&2
  exit 1
}
rm -f "$FIXTURE/abspath-mutation.sh"

# 8. Allow: `sudo firewall-cmd --add-service=ssh` in the already-allowlisted
# rocky-tuning.sh must still be recognized as the approved form -- the sudo
# prefix must not defeat the allowlist's own (anchored) patterns.
cp "$ROOT/packer/scripts/rocky-tuning.sh" "$FIXTURE/packer/scripts/rocky-tuning.sh"
python3 - "$FIXTURE/packer/scripts/rocky-tuning.sh" <<'PY'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    text = fh.read()
text = text.replace(
    "firewall-cmd --permanent --add-service=ssh",
    "sudo firewall-cmd --add-service=ssh",
)
with open(path, "w", encoding="utf-8") as fh:
    fh.write(text)
PY
if ! run_guard; then
  echo "FAIL: 'sudo firewall-cmd --add-service=ssh' (allowlisted form) was flagged" >&2
  cat "$WORKDIR/out.log" >&2
  exit 1
fi
cp "$ROOT/packer/scripts/rocky-tuning.sh" "$FIXTURE/packer/scripts/rocky-tuning.sh"

# 9. Deny: a mutation split across a backslash line continuation must still
# be caught and named at its *first* physical line.
cat > "$FIXTURE/continuation-mutation.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
iptables \
  -F KUBE_READY_EGRESS_UNSCOPED
EOF
if run_guard; then
  echo "FAIL: backslash-continued 'iptables ... -F' was not detected" >&2
  exit 1
fi
grep -q "continuation-mutation.sh:3:.*iptables" "$WORKDIR/out.log" || {
  echo "FAIL: violation report does not name continuation-mutation.sh:3 (the first physical line)" >&2
  cat "$WORKDIR/out.log" >&2
  exit 1
}
rm -f "$FIXTURE/continuation-mutation.sh"

# 10. Deny: a mutation embedded in a .yaml or .conf fixture (image-content
# config formats, not just .sh/.nix/.cfg) must be caught too.
cat > "$FIXTURE/cloud-init-fixture.yaml" <<'EOF'
runcmd:
  - ufw enable
EOF
if run_guard; then
  echo "FAIL: 'ufw enable' in a .yaml fixture was not detected" >&2
  exit 1
fi
grep -q "cloud-init-fixture.yaml:2:.*ufw" "$WORKDIR/out.log" || {
  echo "FAIL: violation report does not name cloud-init-fixture.yaml:2" >&2
  cat "$WORKDIR/out.log" >&2
  exit 1
}
rm -f "$FIXTURE/cloud-init-fixture.yaml"

cat > "$FIXTURE/some.conf" <<'EOF'
# example config
command_line = setenforce 0
EOF
if run_guard; then
  echo "FAIL: 'setenforce 0' in a .conf fixture was not detected" >&2
  exit 1
fi
grep -q "some.conf:2:.*setenforce" "$WORKDIR/out.log" || {
  echo "FAIL: violation report does not name some.conf:2" >&2
  cat "$WORKDIR/out.log" >&2
  exit 1
}
rm -f "$FIXTURE/some.conf"

# .github/workflows content stays excluded even though it's now a scanned
# extension elsewhere -- it runs on the CI runner, never the shipped image.
mkdir -p "$FIXTURE/.github/workflows"
cat > "$FIXTURE/.github/workflows/example.yml" <<'EOF'
jobs:
  test:
    steps:
      - run: sudo iptables -F KUBE_READY_EGRESS
EOF
if ! run_guard; then
  echo "FAIL: .github/workflows content was scanned (should stay excluded -- CI runner, not the image)" >&2
  cat "$WORKDIR/out.log" >&2
  exit 1
fi
rm -rf "$FIXTURE/.github"

echo "host-mutation-guard-test.sh: all scenarios passed"
