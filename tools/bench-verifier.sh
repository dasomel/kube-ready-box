#!/usr/bin/env bash
# 정보 제공용 벤치마크: kube-ready-verifier(Rust) vs tools/node-readiness-attest.sh(bash).
# 러너 편차 때문에 하드 임계값을 걸면 flaky 해지므로 pass/fail 판정은 없다 --
# CI 에서는 non-blocking 스텝으로만 붙인다.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ITERATIONS="${ITERATIONS:-20}"
BIN="${KUBE_READY_VERIFIER_BIN:-$ROOT/rust/kube-ready-verifier/target/release/kube-ready-verifier}"
READINESS_SCRIPT="$ROOT/tools/node-readiness-attest.sh"

[ -x "$BIN" ] || {
  echo "kube-ready-verifier 바이너리를 찾지 못했습니다: $BIN" >&2
  echo "  먼저 빌드하세요: cd rust/kube-ready-verifier && cargo build --release" >&2
  exit 1
}
[ -f "$READINESS_SCRIPT" ] || {
  echo "readiness 스크립트를 찾지 못했습니다: $READINESS_SCRIPT" >&2
  exit 1
}

now_ns() { date +%s%N; }

time_n() {
  local i start end
  for ((i = 0; i < ITERATIONS; i++)); do
    start=$(now_ns)
    "$@" >/dev/null 2>&1 || true
    end=$(now_ns)
    echo $(((end - start) / 1000000))
  done
}

stats() {
  # ms 단위 표본을 stdin 으로 받아 "min mean median p95" 출력 (정수)
  sort -n | awk '
    { a[NR] = $1; sum += $1 }
    END {
      n = NR
      min = a[1]
      mean = sum / n
      if (n % 2 == 1) { median = a[(n + 1) / 2] } else { median = (a[n / 2] + a[n / 2 + 1]) / 2 }
      p95_idx = int(0.95 * n)
      if (p95_idx < 1) p95_idx = 1
      if (p95_idx > n) p95_idx = n
      p95 = a[p95_idx]
      printf "%d %d %d %d\n", min, mean, median, p95
    }'
}

echo "## kube-ready-verifier vs node-readiness-attest.sh (${ITERATIONS} iterations, ms)"
echo

rust_samples=$(time_n "$BIN" preflight)
read -r rust_min rust_mean rust_median rust_p95 <<<"$(stats <<<"$rust_samples")"

shell_samples=$(READINESS_OUTPUT=/tmp/kube-ready-bench-readiness.json time_n bash "$READINESS_SCRIPT")
read -r shell_min shell_mean shell_median shell_p95 <<<"$(stats <<<"$shell_samples")"

printf '| target | min | mean | median | p95 |\n'
printf '|---|---|---|---|---|\n'
printf '| rust_verifier | %d | %d | %d | %d |\n' "$rust_min" "$rust_mean" "$rust_median" "$rust_p95"
printf '| shell_readiness | %d | %d | %d | %d |\n' "$shell_min" "$shell_mean" "$shell_median" "$shell_p95"
echo
echo '```json'
printf '{"schema":"kube-ready-bench/v1","iterations":%d,"unit":"ms","targets":[' "$ITERATIONS"
printf '{"name":"rust_verifier","min":%d,"mean":%d,"median":%d,"p95":%d},' "$rust_min" "$rust_mean" "$rust_median" "$rust_p95"
printf '{"name":"shell_readiness","min":%d,"mean":%d,"median":%d,"p95":%d}' "$shell_min" "$shell_mean" "$shell_median" "$shell_p95"
echo ']}'
echo '```'
