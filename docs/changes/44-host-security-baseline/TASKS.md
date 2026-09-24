# Tasks: Host security baseline — firewall, AppArmor, SELinux and seccomp evidence (#44)

Linked package: [`CHANGE.md`](CHANGE.md). **Accepted 2026-09-24 at revision `41582e4`; tasks may start.**
Each implementation PR covers one requirement group and states the checks it actually ran.

## Inspect and establish evidence

- [ ] `T-001` (`REQ-001..005`) Confirm the gap table's line references against `main` at the time of acceptance.
- [ ] `T-002` (`AC-001`, `AC-003`, `D8`) Capture baseline validator JSON on a built Ubuntu 24.04 box and a
      Rocky 9 box (`bash security/workload-security-check.sh`, `bash network/node-network-readiness.sh`,
      `bash storage/node-storage-readiness.sh`, `bash rocky/preflight.sh`). Record whether `ufw` is
      installed/inactive on Ubuntu. On Rocky, also record `firewalld`'s **runtime and permanent**
      zone, service, port and rich-rule state (`firewall-cmd --list-all` and `--permanent --list-all`)
      as the evidence for the D8 "SSH allowed, preserved intentionally" wording.
- [x] `T-003` Wait for the PR #53 decision. Rebase REQ-002 work on its outcome. **Done**: #53 merged
      as `d561d76`; REQ-002/T-011 rebases on that outcome.
- [ ] `T-004` (`REQ-010`) List consumers of `kube-ready-{security,network,storage,readiness}/v1` status
      (`tools/kube-ready-contracts.sh`, the status publisher, downstream installers) and record them in the PR.

## Implement: additive, non-breaking (PR 1a — first implementation PR)

`T-010`/`T-011` are the first implementation PR. Ship them with their `T-031`/`T-032` tests and the
matching contract-doc updates (`docs/evidence-contracts.md`) in the same PR; they add fields and
never flip an existing check's status.

- [ ] `T-010` (`REQ-001`) Add `firewall_provider` to `network/node-network-readiness.sh`. Check the
      `firewalld`/`ufw` managers before raw `nft`, and keep `firewall_backend` for compatibility.
- [ ] `T-011` (`REQ-002`) Give the nftables branch an enumerated `firewall_state`/`firewall_rules`
      detail (`permission-denied` vs `empty-ruleset`). Absorb PR #53's case if #53 is not merged.
- [ ] `T-012` (`REQ-003`) Add `lsm_stack` from `/sys/kernel/security/lsm` to `security/workload-security-check.sh`.
- [ ] `T-015` (`REQ-007`) Add the host-mutation guard script to `make lint` and CI, matched per
      line/form (not by exempting whole allowlisted files), with the allowlist
      `packer/scripts/rocky-tuning.sh`, `packer/http/rocky-9-*/ks.cfg`, `packer/scripts/00-egress-restrict.sh`
      and `packer/scripts/99-cleanup.sh`. Also cover declarative NixOS settings that disable
      enforcement (e.g. `security.apparmor.enable`/`networking.firewall.enable` toggles in
      `nixos/configuration.nix`; the existing `:106` firewall-disable line stays allowlisted).
- [ ] `T-016` (`REQ-007`) Add an artifact check: no `KUBE_READY_EGRESS` chain after `99-cleanup.sh`.
- [ ] `T-017` (`REQ-005`, `AC-005`) Tighten `sandbox/verify-sandbox-evidence.sh:92`'s regex from
      `Seccomp:[[:space:]]*[12]` to require `Seccomp: 2` for `RuntimeDefault`; add a deny case for a
      pod stuck at `Seccomp: 1`.

## Implement: OS-family classification changes (PR 1b, after REQ-010 consumer notice)

`T-013`/`T-014` are not additive: `T-013` sends alma/fedora hosts into the existing SELinux `FAIL`
path, and `T-014`'s new `seccomp_filter` `FAIL` changes the overall `status`/exit code at
`workload-security-check.sh:85`. Ship these only after `T-004`'s consumer list has been notified
(`REQ-010`), in a PR separate from `T-010`/`T-011`.

- [ ] `T-013` (`REQ-004`) Classify the OS family from `ID`, then `ID_LIKE`, for debian/alma/fedora/centos,
      and add an explicit `nixos` branch.
- [ ] `T-014` (`REQ-005`) Add `seccomp_filter` (filter-mode support). Link the sandbox pod evidence from `security/README.md`.

## Implement: reclassification (PR 2, separate for clean revert)

- [ ] `T-020` (`REQ-003`, `D4`) AppArmor disabled on a capable kernel → `FAIL` in `workload-security-check.sh`,
      `packer/scripts/07-check-tuning.sh` and `09-k8s-node-preflight.sh`. Decided (D4, 2026-09-24):
      unconditional, not gated by `KUBE_READY_SECURITY_PROFILE` or any other input.
- [ ] `T-021` (`REQ-003`) Remove the false PASS for MAC in `storage/node-storage-readiness.sh:39-45`.
      Make `nixos/preflight.sh:82` and `tools/node-readiness-attest.sh:60` read `/sys/module/apparmor/parameters/enabled`.
- [ ] `T-021b` (`REQ-003`) Fix the same false-green in the Rust verifier: `apparmor_check()` in
      `rust/kube-ready-verifier/src/checks/security_time.rs:21` reports `PASS` from
      `/sys/module/apparmor` directory existence alone. Read `/sys/module/apparmor/parameters/enabled`
      as T-021 does for bash, and use the **same deny fixture** as T-020/T-021 so bash and Rust agree
      on a disabled-AppArmor host. Update the function's doc comment (`security_time.rs:15-19`), which
      currently claims the bare existence check is "already correct".
- [ ] `T-022` (`REQ-003`, `REQ-004`, `D5`) Enable AppArmor on NixOS: add
      `security.apparmor.enable = true` to `nixos/configuration.nix` (and `hardened-profile.nix` if it
      overrides LSM settings). No exception record is created for C-09 (decided, D5, 2026-09-24).
  - Verification: build the NixOS image, confirm it **boots successfully**, and confirm
    `apparmor=PASS enabled`, `mac_backend=PASS AppArmor`, and `lsm_stack` contains `apparmor` (allow
    case, AC-003) — status JSON alone is not sufficient. Also confirm containerd/Docker
    (`nixos/configuration.nix:142-143`) actually apply an AppArmor profile to a running container
    (C-12), and run **one workload** under that confinement. Build a fixture/VM with AppArmor left
    disabled and confirm `apparmor=FAIL disabled` (deny case, AC-003). Exercise the **rollback path**:
    revert the enablement commit, rebuild, and confirm the image returns to no-LSM and `FAIL`s under
    REQ-003/004 with no exception route. Record all JSON, boot and workload outputs per T-036.
  - Rollback: revert the enablement commit only (kept separate from the reporting-only REQ-003/004
    changes per rollout order). Reverting returns NixOS to no-LSM, which then `FAIL`s under
    REQ-003/004 with no exception route — call this out explicitly in the PR so it is not mistaken
    for a CI regression.
- [ ] `T-023` (`REQ-010`, `AC-008`) Document the schema as structurally compatible, per D6 (Q3); no bump.

## Verify

- [ ] `T-030` (`AC-006`, all) `shellcheck --severity=warning`, `bash -n`, `make lint`, `./packer/build.sh validate`.
- [ ] `T-031` (`REQ-006`) Add allow and deny cases to `validate.yml` `readiness-negative-tests` for every new
      or reclassified check. Use both fixtures and container runs, per D7 (Q4).
- [ ] `T-032` (`AC-001`, `AC-002`) Run in containers: `ubuntu:24.04` unprivileged and `--privileged`, with
      `ufw` both enabled and inactive, and `nft` present.
- [ ] `T-033` (`AC-003`) Ubuntu Vagrant box: normal boot (allow), then boot with `apparmor=0` (deny).
      Disposable VM, destroyed afterwards.
- [ ] `T-034` (`AC-004`) Rocky 9 Vagrant box: `Enforcing` (allow), then `setenforce 0` (deny), then
      `setenforce 1`, then destroy the VM. Never on a shared host.
- [ ] `T-035` (`AC-005`) Link the `sandbox-enforcement-evidence.yml` run showing `Seccomp: 2` for `RuntimeDefault`.
- [ ] `T-036` Record every run (command, environment, outcome, failures included) in the PR.
      Genuine release-run evidence goes under `release-evidence/`; **deny/experiment evidence
      (deliberately-failing fixtures, e.g. AC-003/AC-004 deny cases) is attached to the PR only and
      never written under `release-evidence/`**, since `tools/openforge-project-status.sh:70` picks
      the newest `PASS`/`FAIL` JSON per capability from that directory without distinguishing a real
      check from a deliberate failure experiment.

## Synchronize durable truth

- [ ] `T-040` (`REQ-008`, `AC-007`) Update `docs/host-security-baseline.md`: OS/LSM matrix from CHANGE.md,
      Rocky default-deny inbound, containerd AppArmor/SELinux obligations, custom-profile verification
      recipe, rollback expectations for installers.
- [ ] `T-041` Update `docs/evidence-contracts.md`, `security/README.md` and `rocky/README.md`.
- [ ] `T-042` Write the ADR in local `docs/adr/` (D9, resolves Q6), covering D1–D10.
- [ ] `T-043` Add release notes that call out the reclassification and the D5 NixOS AppArmor
      enablement (`CHANGELOG.md`).
- [ ] `T-044` Feed reusable gaps (C-01 provider vs backend, C-02 detail vocabulary) back to dasomel/openforge#77.

## Completion review

- [ ] Every REQ maps to an AC with both allow and deny results.
- [ ] Material scope changes were reflected here and re-reviewed.
- [ ] VM-only paths have recorded evidence, not just a claim.
- [ ] N/A items (C-03, C-11, and C-12 for Ubuntu/Rocky only) have owner and review date. C-12 is
      in scope for NixOS (containerd already enabled) — confirm T-022's runtime/workload evidence
      covers it. C-09 is no longer an exception (D5) — confirm NixOS AppArmor enablement evidence
      (T-022) is attached instead.
- [ ] Each PR states the checks actually run and any unverified path.
