#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL="$ROOT/tools/sbom-upgrade-diff.py"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# Exact packages.txt column shape from generate-sbom.sh:39-43.
cat > "$WORKDIR/old.tsv" <<'EOF'
alpha	1.0	amd64	install ok installed
beta	2.0	amd64	install ok installed
gamma	3.0	amd64	install ok installed
libc6	2.36	amd64	install ok installed
libc6	2.36	i386	install ok installed
kernel	6.1-1	arm64	1730000000
kernel	6.2-1	arm64	1730000001
skipme	1	amd64	deinstall ok config-files
EOF
cat > "$WORKDIR/new.tsv" <<'EOF'
alpha	1.1	amd64	install ok installed
delta	4.0	amd64	install ok installed
gamma	3.0	amd64	install ok installed
libc6	2.36	amd64	install ok installed
libc6	2.36	i386	install ok installed
kernel	6.2-1	arm64	1730000001
kernel	6.1-1	arm64	1730000000
skipme	1	amd64	deinstall ok config-files
EOF
python3 "$TOOL" "$WORKDIR/old.tsv" "$WORKDIR/new.tsv" > "$WORKDIR/diff.json"
python3 - "$WORKDIR/diff.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1], encoding="utf-8"))
assert result["added"] == [{"name": "delta", "arch": "amd64", "version": "4.0"}]
assert result["removed"] == [{"name": "beta", "arch": "amd64", "version": "2.0"}]
assert result["changed"] == [{"name": "alpha", "arch": "amd64", "from": "1.0", "to": "1.1"}]
assert result["counts"]["skipped_not_installed"] == 2
assert result["counts"]["total"] > 0
PY

python3 "$TOOL" "$WORKDIR/old.tsv" "$WORKDIR/old.tsv" > "$WORKDIR/same.json"
python3 - "$WORKDIR/same.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1], encoding="utf-8"))
assert result["counts"]["total"] > 0
assert all(not result[key] for key in ("added", "removed", "changed", "license_changed"))
PY

cat > "$WORKDIR/license-old.json" <<'EOF'
{"bomFormat":"CycloneDX","components":[{"name":"alpha","version":"1.0","licenses":[{"license":{"id":"Apache-2.0"}}]}]}
EOF
cat > "$WORKDIR/license-new.json" <<'EOF'
{"bomFormat":"CycloneDX","components":[{"name":"alpha","version":"1.0","licenses":[{"license":{"id":"MIT"}}]}]}
EOF
python3 "$TOOL" --markdown "$WORKDIR/license-old.json" "$WORKDIR/license-new.json" > "$WORKDIR/license.md"

cat > "$WORKDIR/spdx-old.json" <<'EOF'
{"spdxVersion":"SPDX-2.3","packages":[{"name":"alpha","versionInfo":"1","licenseDeclared":"MIT"}]}
EOF
cat > "$WORKDIR/spdx-new.json" <<'EOF'
{"spdxVersion":"SPDX-2.3","packages":[{"name":"alpha","versionInfo":"","licenseDeclared":"MIT"},{"name":"beta"}]}
EOF
python3 "$TOOL" "$WORKDIR/spdx-old.json" "$WORKDIR/spdx-new.json" > "$WORKDIR/spdx.json"

cat > "$WORKDIR/markdown-old.json" <<'EOF'
{"bomFormat":"CycloneDX","components":[{"name":"versioned","version":"1"},{"name":"licensed","version":"1","licenses":[{"license":{"id":"Apache-2.0"}}]},{"name":"removed","version":"9"}]}
EOF
cat > "$WORKDIR/markdown-new.json" <<'EOF'
{"bomFormat":"CycloneDX","components":[{"name":"versioned","version":"2"},{"name":"licensed","version":"1","licenses":[{"license":{"id":"MIT"}}]},{"name":"added","version":"3"}]}
EOF
python3 "$TOOL" --markdown "$WORKDIR/markdown-old.json" "$WORKDIR/markdown-new.json" > "$WORKDIR/all.md"
grep -Fq '| Added | added () |  | 3 |' "$WORKDIR/all.md"
grep -Fq '| Removed | removed () | 9 |  |' "$WORKDIR/all.md"
grep -Fq '| Version | versioned () | 1 | 2 |' "$WORKDIR/all.md"
grep -Fq '| License | licensed () | Apache-2.0 | MIT |' "$WORKDIR/all.md"

: > "$WORKDIR/empty"
printf '{bad json\n' > "$WORKDIR/invalid.json"
printf '{"bomFormat":"CycloneDX","components":{}}\n' > "$WORKDIR/wrong-shape.json"
for bad in empty invalid.json wrong-shape.json; do
  if python3 "$TOOL" "$WORKDIR/$bad" "$WORKDIR/$bad" > /dev/null 2> "$WORKDIR/error"; then
    echo "expected $bad to fail" >&2
    exit 1
  fi
  [ "$(wc -l < "$WORKDIR/error")" -eq 1 ]
  ! grep -q Traceback "$WORKDIR/error"
done

printf 'not an inventory\n' > "$WORKDIR/garbage"
if python3 "$TOOL" "$WORKDIR/garbage" "$WORKDIR/garbage" > /dev/null 2> "$WORKDIR/garbage.err"; then
  echo 'expected garbage input to fail' >&2
  exit 1
fi
grep -Fq 'unsupported TSV row' "$WORKDIR/garbage.err"
grep -Fq '| License | licensed () | Apache-2.0 | MIT |' "$WORKDIR/all.md"
echo 'sbom-upgrade-diff fixtures: PASS'
