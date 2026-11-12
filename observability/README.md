# Optional node observability profile

`observability/node-diagnostic-profile.sh` is intentionally optional and bounded (#20). It collects normalized CPU/memory/disk/network/capability evidence without enabling continuous agents, packet capture or eBPF tracing by default. It is opt-in in `tools/kube-ready-contracts.sh` via `RUN_OBSERVABILITY_PROFILE=1` — the core box and aggregator work identically without it.

Safety properties:

- maximum collection duration: 300 seconds, enforced (`DIAGNOSTIC_DURATION_SECONDS`)
- `DIAGNOSTIC_DURATION_SECONDS` and `DIAGNOSTIC_MAX_BYTES` must be non-negative integers (unset/empty uses the default: 10s / 10MiB); anything else exits 2 before any collection. A duration of 0..300 is accepted, 301+ is rejected (exit 2), never clamped
- bounded evidence size, enforced (`DIAGNOSTIC_MAX_BYTES`, default 10MiB; evidence of exactly that many bytes is accepted, one byte more is refused) — the script refuses to write evidence over the configured bound instead of silently truncating it
- raw command output excluded by default (`raw_output: "excluded-by-default"`) — `checks[]` only ever holds numeric metrics and dpkg package version strings, never captured command output, so there is nothing secret-bearing to redact
- tool/backend versions are read from `dpkg-query`, not by invoking the diagnostic binary itself (some of these tools, e.g. `iftop`/`nethogs`, expect root and a live capture even for a `--version`-style flag; querying the installed package version avoids executing any of them)
- tcpdump/bpftrace/audit capabilities are reported rather than automatically invoked
- unsupported tools and unreadable sources are `UNKNOWN`, not zero or an empty `PASS`; the top-level `status` is `UNKNOWN` (exit code still 0) when none of the core collectors (`cpu`, `memory`, `disk`, `inode`, `network_interfaces`, `network_io`) could measure anything
- output schema: `kube-ready-observability/v1`

Boundary behaviour is covered by `tools/tests/node-diagnostic-profile-test.sh`.

The profile can be connected to #13 readiness and downstream Narwhal/KubeMetal evidence bundles without parsing distro-specific command output.

## What #20 asks for that this does not cover yet

- Fault-injection scenarios (CPU/memory/pressure/disk/network faults) and
  confirming normalized evidence reflects them — needs a real load-generation
  harness, not attempted here.
- Measuring actual collection overhead against a baseline and enforcing a
  budget — the script reports its own `duration_seconds`, but does not
  measure CPU/memory overhead of running it.
- Redaction testing with real secret-bearing tool output — moot for now
  since no raw command output is collected at all (see above), but if a
  future check starts capturing raw tcpdump/audit output this stops being
  automatically true and needs its own redaction pass.
- A privilege model distinguishing which checks need root — every check
  today reads `/proc`/`/sys` or queries dpkg, none require root.
- Ubuntu 24.04/26.04 × Rocky 9/10 parity testing.
- Offline export/import round-trip validation.
