# Kube-ready evidence contracts

All readiness/security/diagnostic validators emit versioned JSON rather than human-only output.

| Contract | Producer | Purpose |
|---|---|---|
| `kube-ready-evidence/v1` | Rust verifier | node preflight + offline artifact verification |
| `kube-ready-readiness/v1` | node readiness / NixOS / Rocky | Kubernetes node readiness |
| `kube-ready-sandbox/v1` | sandbox artifact tooling | sandbox runtime/effective-enforcement evidence |
| `kube-ready-security/v1` | workload security tooling | AppArmor/SELinux/security intent |
| `kube-ready-network/v1` | network profile | effective network state (includes firewall provider/state) |
| `kube-ready-storage/v1` | storage profile | storage/backend capability |
| `kube-ready-time/v1` | time profile | clock synchronization |
| `kube-ready-observability/v1` | diagnostic profile | bounded telemetry evidence |
| `kube-ready-license/v1` | license gate | explicit license policy decision |
| `kube-ready-identity/v1` | first boot | machine identity/SSH evidence |

## Semantics

- `PASS`: the tested property was verified.
- `FAIL`: a required property was explicitly violated.
- `UNKNOWN`: the validator could not establish the property; this is never equivalent to healthy.
- `SKIP`: the check was intentionally not applicable.

A release can only claim a complete readiness result when the required profiles for its declared OS/provider/architecture/runtime/storage combination have no unresolved required `UNKNOWN` results.

Evidence should be linked to the immutable box version and SHA256 digest. Offline replay must consume supplied artifacts only and must not install packages or query external services.

## Enforcement provider boundary

`kube-ready-box` is an **enforcement/evidence provider**, not an agent authorization source of truth. In particular, `kube-ready-sandbox/v1` separates these states:

```text
declared -> supported -> effective -> verified
```

- `declared`: the requested RuntimeClass exists and names a handler.
- `supported`: the handler is one of the explicitly recognized sandbox runtime families.
- `effective`: a workload using that RuntimeClass actually reaches a running container/runtime instance.
- `verified`: effective runtime evidence is accompanied by the required security/resource checks and negative enforcement probe.

The sandbox evidence producer may receive `RESOLUTION_ID` and `INVOCATION_DIGEST` from an upper execution-security layer. They are copied into `correlation` with `authoritySemantics: none-correlation-only`; their presence never authorizes execution and kube-ready-box does not recompute an upstream policy decision.

Each emitted sandbox record also includes `evidenceDigest`, a SHA-256 digest over the canonical JSON evidence object before the digest field is added. Consumers can therefore bind the effective enforcement result to their own decision/invocation chain without making this node image the policy authority.

The `missing-runtime-class` negative probe demonstrates the Kubernetes/runtime enforcement boundary. It explicitly does **not** prove that an upstream request was correctly authorized or denied; request-side authorization must be tested separately by the agent/control-plane repository.

## Network firewall evidence (`kube-ready-network/v1`, #44 T-010/T-011)

`network/node-network-readiness.sh` reports four related, additive firewall checks; none of them ever emits `FAIL`.

- `firewall_backend`: the legacy packet-filter-backend precedence, unchanged since before #44 -- `nft` present wins (`PASS nftables`), else `firewall-cmd` (`PASS firewalld`), else `ufw` (`PASS ufw`), else `UNKNOWN unavailable`. Because `firewalld`/`ufw` are themselves `nft`-backed, this check alone cannot say which manager actually owns the ruleset.
- `firewall_provider` (new): names the manager that actually owns enforcement, checked in this precedence order so `firewalld`/`ufw` are never masked as `nftables`:
  1. `firewall-cmd --state` reports `running` -> `PASS firewalld`.
  2. else `ufw status`'s first line is `Status: active` -> `PASS ufw`.
  3. else, if `nft` is present and `nft list ruleset` succeeds with a non-empty ruleset -> `UNKNOWN external` (an externally managed raw ruleset exists, but no recognized manager owns it).
  4. else, if that query succeeds and the ruleset is empty, or `nft` is absent -> `UNKNOWN none`.
  5. else, if `nft` is present but the query itself fails -> `UNKNOWN status-unavailable` (evidence is insufficient to claim `none`).

  `firewall_provider` never reports `nftables` as a `PASS`.
- `firewall_state`: always emitted, for the active provider if one is active, otherwise for the highest-precedence *installed* manager (`firewalld` before `ufw`): `firewalld` `running`/`not running`/other -> `PASS running`/`UNKNOWN inactive`/`UNKNOWN status-unavailable`; `ufw` active/inactive/empty-stdout/other -> `PASS running`/`UNKNOWN inactive`/`UNKNOWN status-unavailable`/`UNKNOWN <line>` (PR #53's table, unchanged); no manager installed -> `UNKNOWN tool-absent`.
- `firewall_rules` (detail vocabulary expanded by T-011): the raw `nft` ruleset, independent of which manager owns it. `nft` absent -> `UNKNOWN tool-absent`; query fails with a permission error (stderr matching `Operation not permitted`/`Permission denied`) -> `UNKNOWN permission-denied`; any other query failure -> `UNKNOWN status-unavailable`; query succeeds with an empty ruleset -> `UNKNOWN empty-ruleset` (a successful check of nothing, distinct from a failed query); query succeeds non-empty -> `PASS present`.

Deterministic fixture coverage lives in `tools/tests/network-firewall-detection-test.sh` (wired into `make test` and CI); container evidence for unprivileged vs `--privileged` runs is recorded per-PR per T-032.

## Kernel LSM stack evidence (`kube-ready-security/v1`, #44 T-012)

`security/workload-security-check.sh` reports `lsm_stack`, an additive-only check that reads the
kernel's active LSM stack from securityfs. It is independent of the existing `mac_backend`/
`apparmor`/`selinux` classification and **never emits `FAIL`** -- adding it does not change any
other check's status or the overall `status`/exit code.

- Readable and non-empty (`/sys/kernel/security/lsm`, e.g. `lockdown,capability,landlock,yama,apparmor,integrity`) -> `PASS <raw comma list>`.
- Path absent (securityfs not mounted, or the kernel predates this file) -> `UNKNOWN securityfs-absent`.
- Path exists but cannot be read -> `UNKNOWN permission-denied`.
- Read succeeds but returns nothing -> `UNKNOWN empty-stack`.

The securityfs path is not overridable by any environment variable (D7: no production-settable
evidence-source bypass). Deterministic fixture coverage lives in
`tools/tests/workload-lsm-stack-test.sh` (wired into `make test` and CI), which drives the allow
and deny cases via a PATH-shimmed `cat` rather than a script input.

## Native LSM family and seccomp filter support (`kube-ready-security/v1`, #44 T-013/T-014)

`security/workload-security-check.sh` chooses AppArmor for Ubuntu, Debian and NixOS, and SELinux
for Rocky, RHEL, Alma, Fedora and CentOS. It checks `/etc/os-release` `ID` first, then the ordered
tokens in `ID_LIKE`; an unrecognized family remains `UNKNOWN`.

The additive `seccomp_filter` check reports `PASS` when `/proc/self/status` contains a numeric
`Seccomp_filters` field or, on older kernels, `actions_avail` contains both `errno` and
`kill_process`. If neither signal exists on a known Linux kernel, it reports `FAIL`; when proc
evidence is unavailable, it reports `UNKNOWN kernel-unavailable`. This reports node capability,
not whether a workload actually runs with `RuntimeDefault`.

`tools/tests/workload-security-classification-test.sh` covers direct and `ID_LIKE` family mapping,
the disabled-SELinux deny case, both seccomp allow paths, missing filter support and unavailable
kernel evidence. It runs the real validator with only its OS/proc data paths redirected to fixtures.

## Disabled/permissive native LSM reclassification (`kube-ready-security/v1`, `kube-ready-storage/v1`, `kube-ready-evidence/v1`, #44 T-020/T-021/T-021b, D4)

A disabled AppArmor or a permissive/disabled SELinux on its native, capable host is now `FAIL`,
never `PASS` and never the generic `UNKNOWN` used for "cannot determine". This is a **behavioral**
change (existing green runs on a host with a disabled/permissive LSM turn `FAIL`); the schema
itself is unchanged -- `kube-ready-security/v1` keeps every existing check ID and field type, so
this stays structurally compatible per D6 and does not bump to `v2`.

- **Unconditional**: not gated by `KUBE_READY_SECURITY_PROFILE` or any other input (D4). There is
  no `standard`-profile fallback to `UNKNOWN`/`PASS` for a disabled or permissive LSM on a capable
  kernel.
- **AppArmor** (`security/workload-security-check.sh`'s `apparmor` check, `packer/scripts/07-check-tuning.sh`
  and `09-k8s-node-preflight.sh`'s embedded `apparmor` check, `nixos/preflight.sh`,
  `tools/node-readiness-attest.sh`, and the Rust verifier's `apparmor` check): read
  `/sys/module/apparmor/parameters/enabled` (`Y`/`N`), not `aa-status` and not bare
  `/sys/module/apparmor` directory existence. `Y` -> `PASS enabled`; `N` -> `FAIL disabled`;
  unreadable (no such file, kernel lacks AppArmor, container without the module) -> `UNKNOWN
  <reason>`, never `FAIL` and never `PASS`.
- **`mac_backend`** (`security/workload-security-check.sh`, `storage/node-storage-readiness.sh` --
  check ID stays `mac_backend` in both): now mirrors the same enabled/disabled state instead of
  unconditionally naming the backend as `PASS`. SELinux `Permissive`/`Disabled` -> `FAIL`; AppArmor
  `N` -> `FAIL`.
- **`selinux_policy`** (`security/workload-security-check.sh`, C-07): in addition to the existing
  forward-drift `FAIL` (config wants `enforcing`, runtime is permissive/disabled), the reverse
  drift -- config no longer wants `enforcing` while the running kernel is still `Enforcing`, which
  is lost on the next boot -- is also `FAIL`. A `getenforce` query failure is `UNKNOWN <reason>`,
  never `PASS`.
- **Rust verifier parity** (`rust/kube-ready-verifier/src/checks/security_time.rs`): the `apparmor`
  check reads the same `/sys/module/apparmor/parameters/enabled` value and applies the same
  PASS/FAIL/UNKNOWN mapping as the bash check, so the two implementations agree on a disabled-
  AppArmor host. Covered by unit tests (`classify_apparmor_enabled`) for enabled/disabled/
  unreadable/unexpected-value.

Deterministic allow/deny fixture coverage lives in `tools/tests/workload-security-classification-test.sh`
(extended) and `tools/tests/node-storage-mac-backend-test.sh` (new), wired into `make test` and CI,
per REQ-006/D7 -- unreachable paths (a live Rocky SELinux toggle, a kernel `apparmor=0` boot) are
shimmed via PATH/fixture rather than mutating a shared host, with separate recorded VM/container
evidence for the paths a fixture cannot reach.

**Known consumers notified (REQ-010/AC-008)**: `tools/kube-ready-contracts.sh`'s `security` report
(runs `security/workload-security-check.sh` and passes its `status` through unchanged),
`tools/openforge-project-status.sh` (the OpenForge status publisher, which reads that aggregated
`workload-security` report's `PASS`/`FAIL` status to set the `workload-security` capability's
`verification.runtime` field), and the CI `readiness-negative-tests`/aggregate-contract-runner jobs
in `.github/workflows/validate.yml`. Downstream cluster installers consuming `kube-ready-security/v1`
per `docs/host-security-baseline.md`'s hand-off are the other named consumer class (CHANGE.md
"Affected consumers"). See `CHANGELOG.md` for the release-facing notice.

## Seccomp `RuntimeDefault` effective mode (`kube-ready-sandbox/v1`, #44 T-017)

`sandbox/verify-sandbox-evidence.sh`'s pod-level `seccompNoNewPrivs` check now requires
`Seccomp: 2` (filtering, the kernel's enforced-default mode) in `/proc/self/status` inside the
pod, alongside `NoNewPrivs: 1`. It previously accepted `Seccomp:[[:space:]]*[12]`, which let a pod
stuck at mode `1` (strict) report `PASS` even though it never actually applied the
`RuntimeDefault` seccomp profile. A pod stuck at mode `1` now reports `checks.seccompNoNewPrivs`,
`lifecycle.verified` and the overall `status` as `FAIL`, not `PASS`.

Deterministic fixture coverage (both the mode-`2` allow case and the mode-`1` deny case) lives in
`tools/tests/sandbox-seccomp-mode-test.sh` against a PATH-stubbed `kubectl`, wired into `make test`
and CI; no cluster is required. The cluster-level `Seccomp: 2` allow case is also linked from
`security/README.md` per T-035.
