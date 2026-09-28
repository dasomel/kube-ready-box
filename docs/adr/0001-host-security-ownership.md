# ADR-0001: Host Security Ownership

- Status: Accepted
- Accepted: 2026-09-24
- Change package revision: `41582e4`
- Related: Issue #44; [OpenForge ADR-0014 (Kubernetes Zero Trust baseline)](https://github.com/dasomel/openforge)

## Context

Kube-ready-box supplies host security evidence and preserves native controls. It does not know
the cluster topology or CNI at image-build time, so it cannot safely generate a universal
firewall policy. Ubuntu and Rocky base images do not ship containerd; runtime LSM integration
belongs to the installer where the installer supplies the runtime. NixOS enables AppArmor
(T-022).

Before #44, evidence could report a disabled native LSM as healthy, mask `firewalld` or `ufw`
behind the `nft` backend, and leave several OS families unclassified. Issue #44 corrects those
reports and documents the hand-off. Reclassifying existing checks from `UNKNOWN` to `FAIL` is
behaviorally significant even though the evidence schema remains structurally compatible.

This ADR records the accepted decisions in the pinned Change Package. The package is the source
for decision wording and scope; this ADR is the durable local record.

## Decision

### D1 — Observe and preserve firewall state

- **Decision:** Observe and preserve; never generate firewall policy.
- **Reason:** Cluster ports depend on topology and CNI, which are unknown at image-build time.
- **Cost:** Ubuntu and NixOS ship with no active host firewall.
- **Escape hatch:** Re-review C-03 by 2026-12-31, or earlier if kube-ready-box starts shipping an installer/CNI.

### D2 — Disabled native LSM is a failure

- **Decision:** A disabled LSM on a native-capable kernel is `FAIL`, not `UNKNOWN`.
- **Reason:** A capable host with disabled MAC is an explicit policy violation, not missing evidence.
- **Cost:** Some existing green runs turn red.
- **Escape hatch:** Record a REQ-009 exception with owner, reason, and expiry, schema-compatible per D6; no profile switch is allowed per D4.

### D3 — Prove unreachable paths with evidence

- **Decision:** Prove paths CI cannot reach with recorded container or VM evidence, not test-only hooks in production scripts.
- **Reason:** Fixtures test classification logic; real environments prove enforcement.
- **Cost:** Evidence must be collected for paths ordinary CI cannot exercise.
- **Escape hatch:** Record a genuinely unreachable path as VM-only evidence; do not add a production-check bypass input.

### D4 — LSM failure is unconditional

- **Decision:** Disabled AppArmor or permissive/disabled SELinux is `FAIL`, regardless of `KUBE_READY_SECURITY_PROFILE` or other input.
- **Reason:** Profile-gating could let a `standard` run mask unenforced MAC on a capable kernel and recreate the false-green defect.
- **Cost:** Previously green runs on affected hosts fail immediately, with no `standard` fallback to `UNKNOWN`.
- **Escape hatch:** No profile switch; use a time-bound REQ-009 exception or revert the separate reclassification commit.

### D5 — Enable AppArmor on NixOS

- **Decision:** NixOS images enable `security.apparmor.enable = true`; they do not carry a permanent C-09 exception.
- **Reason:** AppArmor is available on NixOS, so the same native-LSM rule used for Ubuntu/Rocky applies.
- **Cost:** This changes shipped image enforcement and carries module-availability and hardened-kernel compatibility risk; it needs allow, deny, and rollback evidence (T-022).
- **Escape hatch:** Revert the separate NixOS enablement commit; no permanent C-09 exception remains.

### D6 — Schema compatibility is structural

- **Decision:** Reclassifying existing check IDs is structurally compatible with `kube-ready-security/v1`; do not bump the schema.
- **Reason:** IDs and types stay unchanged; consumers pass through parsed JSON and the risk is their reaction to changed status/exit codes.
- **Cost:** Notify downstream consumers and provide status, exit-code, and ID regression coverage (REQ-010, T-004).
- **Escape hatch:** Revert the reclassification; reconsider `v2` if an ID is deleted or its type changes.

### D7 — Pair deterministic fixtures with runtime evidence

- **Decision:** For unreachable deny paths, use both deterministic CI fixtures and separate recorded VM/container enforcement evidence.
- **Reason:** CI needs repeatable classification coverage; only a real VM/container proves enforcement.
- **Cost:** Fixtures must track the real check logic.
- **Escape hatch:** If a path remains genuinely unreachable even with a fixture, record it as VM-only per D3; add no production bypass input.

### D8 — Describe Rocky firewall precisely

- **Decision:** Describe Rocky as “`firewalld` active with SSH allowed, preserved intentionally,” not “ssh-only.”
- **Reason:** Source adds SSH but does not remove or verify other default-zone services or ports.
- **Cost:** T-002 captures runtime and permanent zone, service, port, and rich-rule state.
- **Escape hatch:** Rocky policy stays unchanged; tighten the wording only after that evidence is captured.

### D9 — Keep the ADR local

- **Decision:** Create this ADR in the repository's `docs/adr/`, covering D1–D10.
- **Reason:** Local evidence and host-security contracts own the behavior this change governs; colocating decisions keeps them traceable.
- **Cost:** One additional short ADR to maintain.
- **Escape hatch:** Cross-link an OpenForge-side ADR for higher-level policy changes; keep this local implementation record.

### D10 — Keep the Change Package PR-only

- **Decision:** Keep the `CHANGE.md`/`TASKS.md` package in the PR, pinned by revision, rather than merging it as durable `docs/changes/` documentation.
- **Reason:** Accepted decisions and scope are absorbed into durable host-security docs, evidence contracts, and this ADR; this avoids a duplicate long-lived specification tree.
- **Cost:** Readers locate the working package by PR and revision rather than a stable document path.
- **Escape hatch:** If tracking spans enough PRs to become unmanageable, merge a temporary package document and fold it into durable docs after implementation.

## Consequences

### Image guarantees

- Validators report the owning firewall provider separately from the packet-filter backend, with actionable evidence details.
- Native AppArmor/SELinux state is classified from OS family. A disabled/permissive native LSM on a capable kernel fails; unknown evidence is not healthy.
- The kernel LSM stack and seccomp filter-mode capability are reported. Pod-level `RuntimeDefault` effectiveness is verified by the sandbox path, which requires `Seccomp: 2`.
- Ubuntu receives no firewall policy. Rocky retains its existing `firewalld` policy with SSH allowed; do not describe it as exclusively SSH-only without zone evidence.
- NixOS enables AppArmor (T-022).

### Installer ownership

- The installer owns firewall enforcement and required ports for the actual cluster topology. It must inspect and stage policy safely, retain an out-of-band console, and snapshot rules before changes. Rocky's inbound defaults may block Kubernetes and CNI ports.
- Where the installer supplies containerd, it configures and verifies AppArmor or SELinux runtime integration. The image does not install containerd into Ubuntu/Rocky base boxes.
- The installer distributes custom AppArmor profiles to eligible nodes and verifies the profile is present (for example with `aa-status --json`).
- The installer applies workload-scoped `seLinuxOptions` where required and gates deployment on the documented evidence contract. Rollback expectations belong to the installer hand-off.
- No claim is made here about NixOS containerd confinement beyond D5's AppArmor enablement.

### Compatibility and alternatives

Existing consumers may turn red when disabled/permissive LSM states change from `UNKNOWN` or `PASS` to `FAIL`. Schema IDs and types remain unchanged; downstream consumers must be notified. Exceptions require owner, reason, and expiry, and never suppress the underlying state without a valid record.

Rejected alternatives:

- Ship a “Kubernetes ports” firewall profile in the image: CNI topologies differ, and #44 explicitly forbids universal firewall policy.
- Disable Rocky SELinux for runtime compatibility: #44 and OpenForge #77 §6 forbid it.

## Implementation

- PR #56 — report firewall provider and enumerated firewall evidence.
- PR #58 — report kernel LSM stack and require seccomp filter mode.
- PR #59 — guard against blind host firewall/LSM mutation.
- PR #60 — classify native LSM by OS family and report seccomp filter support.
- PR #61 — fail on disabled or permissive native LSM; preserve schema structure.
- T-022 — enable AppArmor on NixOS.

