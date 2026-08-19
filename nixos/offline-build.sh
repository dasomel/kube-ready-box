#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# No network access is intentionally requested here. The caller must supply a
# populated Nix store/cache containing the exact flake inputs first.
command -v nix >/dev/null || { echo 'nix is required' >&2; exit 2; }
nix --extra-experimental-features 'nix-command flakes' flake metadata --offline
nix --extra-experimental-features 'nix-command flakes' flake check --offline
nix --extra-experimental-features 'nix-command flakes' build --offline '.#packages.x86_64-linux.vagrant-virtualbox'
