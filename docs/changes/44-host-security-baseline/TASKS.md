# Tasks: Host security baseline — firewall, AppArmor, SELinux and seccomp evidence (#44)

Linked package: [`CHANGE.md`](CHANGE.md). **No task starts until the package is accepted.**
Each implementation PR covers one requirement group and states the checks it actually ran.

## Inspect and establish evidence

- [ ] `T-001` (`REQ-001..005`) Confirm the gap table's line references against `main` at the time of acceptance.
- [ ] `T-002` (`AC-001`, `AC-003`) Capture baseline validator JSON on a built Ubuntu 24.04 box and a
      Rocky 9 box (`bash security/workload-security-check.sh`, `bash network/node-network-readiness.sh`,
      `bash storage/node-storage-readiness.sh`, `bash rocky/preflight.sh`). Record whether `ufw` is installed/inactive on Ubuntu.
- [ ] `T-003` Wait for the PR #53 decision. Rebase REQ-002 work on its outcome.
- [ ] `T-004` (`REQ-010`) List consumers of `kube-ready-{security,network,storage,readiness}/v1` status
      (`tools/kube-ready-contracts.sh`, the status publisher, downstream installers) and record them in the PR.

## Implement: additive, non-breaking (PR 1)

- [ ] `T-010` (`REQ-001`) Add `firewall_provider` to `network/node-network-readiness.sh`. Check the
      `firewalld`/`ufw` managers before raw `nft`, and keep `firewall_backend` for compatibility.
- [ ] `T-011` (`REQ-002`) Give the nftables branch an enumerated `firewall_state`/`firewall_rules`
      detail (`permission-denied` vs `empty-ruleset`). Absorb PR #53's case if #53 is not merged.
- [ ] `T-012` (`REQ-003`) Add `lsm_stack` from `/sys/kernel/security/lsm` to `security/workload-security-check.sh`.
- [ ] `T-013` (`REQ-004`) Classify the OS family from `ID`, then `ID_LIKE`, for debian/alma/fedora/centos,
      and add an explicit `nixos` branch.
- [ ] `T-014` (`REQ-005`) Add `seccomp_filter` (filter-mode support). Link the sandbox pod evidence from `security/README.md`.
- [ ] `T-015` (`REQ-007`) Add the host-mutation guard script to `make lint` and CI, with the allowlist
      `packer/scripts/rocky-tuning.sh`, `packer/http/rocky-9-*/ks.cfg`, `packer/scripts/00-egress-restrict.sh` and `packer/scripts/99-cleanup.sh`.
- [ ] `T-016` (`REQ-007`) Add an artifact check: no `KUBE_READY_EGRESS` chain after `99-cleanup.sh`.

## Implement: reclassification (PR 2, separate for clean revert)

- [ ] `T-020` (`REQ-003`) AppArmor disabled on a capable kernel → `FAIL` in `workload-security-check.sh`,
      `packer/scripts/07-check-tuning.sh` and `09-k8s-node-preflight.sh`. Gate this on the Q1 decision.
- [ ] `T-021` (`REQ-003`) Remove the false PASS for MAC in `storage/node-storage-readiness.sh:39-45`.
      Make `nixos/preflight.sh:82` and `tools/node-readiness-attest.sh:60` read `/sys/module/apparmor/parameters/enabled`.
- [ ] `T-022` (`REQ-009`, `C-09`) Implement the NixOS decision from Q2: either the exception record or
      `security.apparmor.enable` with its own allow/deny/rollback evidence.
- [ ] `T-023` (`REQ-010`) Bump the schema, or document it as compatible, per Q3.

## Verify

- [ ] `T-030` (`AC-006`, all) `shellcheck --severity=warning`, `bash -n`, `make lint`, `./packer/build.sh validate`.
- [ ] `T-031` (`REQ-006`) Add allow and deny cases to `validate.yml` `readiness-negative-tests` for every new
      or reclassified check. Use fixtures or container runs per Q4.
- [ ] `T-032` (`AC-001`, `AC-002`) Run in containers: `ubuntu:24.04` unprivileged and `--privileged`, with
      `ufw` both enabled and inactive, and `nft` present.
- [ ] `T-033` (`AC-003`) Ubuntu Vagrant box: normal boot (allow), then boot with `apparmor=0` (deny).
      Disposable VM, destroyed afterwards.
- [ ] `T-034` (`AC-004`) Rocky 9 Vagrant box: `Enforcing` (allow), then `setenforce 0` (deny), then
      `setenforce 1`, then destroy the VM. Never on a shared host.
- [ ] `T-035` (`AC-005`) Link the `sandbox-enforcement-evidence.yml` run showing `Seccomp: 2` for `RuntimeDefault`.
- [ ] `T-036` Record every run (command, environment, outcome, failures included) in the PR or under `release-evidence/`.

## Synchronize durable truth

- [ ] `T-040` (`REQ-008`, `AC-007`) Update `docs/host-security-baseline.md`: OS/LSM matrix from CHANGE.md,
      Rocky default-deny inbound, containerd AppArmor/SELinux obligations, custom-profile verification
      recipe, rollback expectations for installers.
- [ ] `T-041` Update `docs/evidence-contracts.md`, `security/README.md` and `rocky/README.md`.
- [ ] `T-042` Write the ADR (location per Q6) for D1–D3.
- [ ] `T-043` Add release notes that call out the reclassification (`CHANGELOG.md`).
- [ ] `T-044` Feed reusable gaps (C-01 provider vs backend, C-02 detail vocabulary) back to dasomel/openforge#77.

## Completion review

- [ ] Every REQ maps to an AC with both allow and deny results.
- [ ] Material scope changes were reflected here and re-reviewed.
- [ ] VM-only paths have recorded evidence, not just a claim.
- [ ] N/A items (C-03, C-11, C-12) and the C-09 exception have owner and review date.
- [ ] Each PR states the checks actually run and any unverified path.
