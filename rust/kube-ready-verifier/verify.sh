#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
command -v cargo >/dev/null 2>&1 || { echo 'cargo is required to build the verifier' >&2; exit 2; }
cargo build --release --offline
exec "$ROOT/target/release/kube-ready-verifier" "$@"
