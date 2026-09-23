# Change: Host security baseline — firewall, AppArmor, SELinux and seccomp evidence (#44)

- Change class: `D` — security boundary: it changes which host-security states the shipped
  images and their validators report as healthy, and it fixes the firewall/LSM ownership
  boundary between kube-ready-box and cluster installers.
- Owner: @dasomel
- Related issue: #44 (source of truth: dasomel/openforge#77, `docs/kubernetes-zero-trust-security-baseline.md`)
- Status: `Draft` — **awaiting acceptance; no implementation in this package**
- Accepted by / date: —

This package follows the OpenForge short-lived Change Package lifecycle
(`docs/change-management.md` in dasomel/openforge). It is a working artifact for review; see
open question Q7 on whether it is merged or kept only in the PR.

## Problem

OpenForge #77 sets the `production` profile to: seccomp `RuntimeDefault` required; AppArmor or
SELinux **enforcing where supported**; host OS firewall **required where the host is managed**;
and no blind firewall mutation on an unknown topology.

Part of #44 has already landed on `main` (`2a2c917`: `docs/host-security-baseline.md` and `ufw`
detection). That work was recorded as reviewed only. PR #53, which is in flight, fixes one
empty-evidence defect in it. The inventory below shows that the rest of the evidence is not yet
fit to gate a production profile:

1. **False-green MAC states.** Several validators report an absent or disabled LSM as `PASS`.
2. **The firewall provider is masked.** The `nft` binary takes precedence, so `firewalld` (Rocky)
   and `ufw` (Ubuntu) are never named as the owning provider.
3. **Validators recognize only some OS families.** Debian/Alma/Fedora/NixOS hosts fall through to
   `UNKNOWN`.
4. **No deterministic deny tests exist for LSM or firewall.** CI proves only the
   `privileged_workload` mutation.
5. **The hand-off contract has gaps.** It does not say that Rocky ships default-deny inbound
   (ssh only), or that containerd's LSM integration is left to the installer.

## Intent

kube-ready-box stays an **observe-and-preserve evidence provider**. It keeps each image's
host-native LSM enforcing and never ships a generic firewall policy. It reports firewall, LSM and
seccomp state truthfully: no false `PASS`, and an actionable detail on every `UNKNOWN`. Negative
tests prove every classification. A written contract tells a cluster installer exactly what it
inherits and what it must provide.

## Supported host OS matrix and LSM model

| Image | Build source | Arch / provider | Native LSM (preserved) | Firewall as shipped |
|---|---|---|---|---|
| Ubuntu 24.04 (default) / 26.04 | `packer/{virtualbox,vmware}-{amd64,arm64}.pkr.hcl`, ISO map `packer/plugins.pkr.hcl:85-100` | amd64+arm64 / VirtualBox+VMware | **AppArmor**: packages pinned in `packer/scripts/01-base.sh:66-74` and `03-os-packages.sh:49` | No policy from kube-ready-box. The distro default is `ufw` installed but inactive (**to verify on a built box**, T-002) |
| Rocky 9 | `packer/rocky-{virtualbox,vmware}-arm64.pkr.hcl`, `packer/http/rocky-9-{ext4,xfs}/ks.cfg` | arm64 / VirtualBox+VMware | **SELinux `Enforcing`**: `ks.cfg:11` and `packer/scripts/rocky-tuning.sh:13-22` | `firewalld` active and **ssh only**: `ks.cfg:12` and `rocky-tuning.sh:28-37`. Inbound is effectively default-deny for kubelet, API server and CNI ports |
| Rocky 10 | reserved, rejected by validation (`packer/plugins.pkr.hcl:106-110`) | — | N/A until built (SELinux when added) | N/A |
| NixOS | `nixos/configuration.nix` (+ `hardened-profile.nix`) | per `build-nixos.yml` | **AppArmor, enabled (D5, 2026-09-24)**: `security.apparmor.enable = true` is required in `configuration.nix`; currently absent — T-022 adds it | Firewall disabled (`configuration.nix:106`, "K8s CNI manages iptables/nftables") |
| Debian / RHEL / Alma / Fedora (bring-your-own host running the validators) | not built here | — | Debian = AppArmor; RHEL/Alma/Fedora = SELinux `Enforcing` | Classified, never configured |

LSM rule (`REQ-004`): the model is chosen by OS family from `ID`/`ID_LIKE`. It is never
"whichever tool is installed", and it is never switched. SELinux is never set to
`Permissive`/`Disabled`, and AppArmor is never disabled, as a compatibility workaround.

## Control-by-control gap table

| ID | Control | Current state (evidence) | Target | Disposition |
|---|---|---|---|---|
| C-01 | Firewall **provider** identification | `network/node-network-readiness.sh:19-31`: `nft` is checked first. On Rocky, `firewalld` (nft-backed) is reported as `nftables`. PR #53 notes that the `ufw` branch is unreachable wherever `nft` exists | Report `firewall_provider` (`firewalld`/`ufw`/`nftables`/`external`/`none`) separately from the packet-filter backend. Check the managers (`firewalld`, `ufw`) before raw `nft` | Gap → REQ-001 |
| C-02 | Firewall **state** is actionable | Empty `ufw` stdout gives an empty `UNKNOWN` (fixed by **PR #53**, `status-unavailable`). The `nftables` branch emits no `firewall_state`. An unprivileged `nft list ruleset` gives `firewall_rules UNKNOWN empty`, which cannot be told apart from a truly empty ruleset | Every firewall check carries a distinguishing detail (`inactive`, `status-unavailable`, `permission-denied`, `empty-ruleset`) | Gap → REQ-002 (builds on #53) |
| C-03 | Host firewall **enforcement** on shipped images | Ubuntu: none active. NixOS: disabled. Rocky: `firewalld` ssh-only | No change. Required ports depend on cluster topology and CNI, which are unknown at image-build time (OpenForge #77 §2: "generated from the actual cluster topology… never a hard-coded universal port list") | **N/A for kube-ready-box enforcement.** The installer owns it (REQ-008). Time bound: re-review by **2026-12-31**, or earlier if kube-ready-box starts shipping an installer/CNI |
| C-04 | Rocky's default-deny inbound is disclosed | `docs/host-security-baseline.md` says kube-ready-box "does not open… ports". It does not say that Rocky blocks 6443/10250/CNI ports by default | The hand-off states this explicitly and gives a verification command | Gap → REQ-008 |
| C-05 | AppArmor enabled on AppArmor-native images | `security/workload-security-check.sh:8-16`: `mac_backend PASS AppArmor` is emitted even when AppArmor is disabled, and a disabled AppArmor is only `UNKNOWN`. Same pattern in `packer/scripts/07-check-tuning.sh:186-193` and `09-k8s-node-preflight.sh:71-73`. The kernel LSM stack (`/sys/kernel/security/lsm`) is never read | Enabled → `PASS`. Tooling cannot tell → `UNKNOWN <reason>`. **Enabled-capable kernel but AppArmor disabled → `FAIL`** under the production profile. Record the LSM stack | Gap → REQ-003 |
| C-06 | No false-green in secondary validators | `storage/node-storage-readiness.sh:39-45`: `PASS apparmor:disabled` and `PASS selinux:Permissive/Disabled`. `nixos/preflight.sh:82` and `tools/node-readiness-attest.sh:60` treat the existence of `/sys/module/apparmor` as "loaded", even when AppArmor is disabled at boot | Same classification as C-05. If the check stays informational, the ID is renamed so it cannot be read as a policy PASS | Gap → REQ-003 |
| C-07 | SELinux `Enforcing` on SELinux-native images | Already correct in `workload-security-check.sh:11-15` and `rocky/preflight.sh:11-32` (`Permissive`/`Disabled` → `FAIL`, config/runtime drift → `FAIL`). The family match is limited to `rocky`/`rhel` | Keep. Widen the family detection to `ID_LIKE` (alma, fedora, centos) | Gap (partial) → REQ-004 |
| C-08 | OS-family classification | Only `ubuntu`, `rocky` and `rhel` are recognized (`workload-security-check.sh:8-16`). `debian` and `nixos` → `mac_backend UNKNOWN` | Explicit mapping, with NixOS classified on purpose (see C-09) | Gap → REQ-004 |
| C-09 | NixOS LSM | No LSM is enabled. The validators report it as UNKNOWN or as a misleading "loaded" (C-06) | **Decided (D5, 2026-09-24): enable `security.apparmor.enable = true`.** Enabled → `PASS` under the same REQ-003 rule as Ubuntu; no exception is recorded for this state | Gap → REQ-003, REQ-004. Enablement is an enforcement change, not reporting-only; needs its own allow/deny/rollback evidence (T-022) |
| C-10 | seccomp node prerequisite | `workload-security-check.sh`: `seccomp` checks only for the `Seccomp:` line; `seccomp_capability` lists `actions_avail` | Also assert filter mode (`CONFIG_SECCOMP_FILTER`: the `Seccomp_filters:` field or `actions_avail` contains `errno` and `kill_process`). Missing → `FAIL` when the kernel is known | Gap → REQ-005 |
| C-11 | seccomp `RuntimeDefault` **effective** | Covered only by the pod-level path in `sandbox/verify-sandbox-evidence.sh:74-92`, which needs a cluster | Keep at pod level and link from the host evidence. A node-only image cannot prove it (`security/README.md`) | **N/A at image level.** Covered by the cluster path, per the existing `declared→…→verified` contract |
| C-12 | Runtime LSM integration (containerd AppArmor default profile, `enable_selinux`, `container-selinux`) | containerd is not in the base box (`packer/scripts/07-check-tuning.sh:234`) | Check it when a runtime is present. Otherwise it is an installer obligation in the hand-off contract | **N/A at image level.** Installer obligation (REQ-008). Re-evaluate if the base box ever ships containerd |
| C-13 | Custom AppArmor profile distribution / `seLinuxOptions` | Documented in `docs/host-security-baseline.md` ("Cluster-installer hand-off") | Keep the doc. Add the verification recipe (`aa-status --json` profile name present on every eligible node) | Docs → REQ-008 |
| C-14 | Deterministic allow/deny tests | CI asserts only `privileged_workload` PASS/FAIL and `firewall_backend` non-FAIL (`.github/workflows/validate.yml:416-448`) | Every new classification has a PASS case and a FAIL/UNKNOWN case in CI | Gap → REQ-006 |
| C-15 | No blind host mutation | The mutations that exist are all scoped: `rocky-tuning.sh` (Rocky build), `ks.cfg`, build-time egress `00-egress-restrict.sh` (opt-in, `plugins.pkr.hcl:138-147`) removed by `99-cleanup.sh:14-16` | A static guard fails CI when a firewall or LSM mutation command appears outside an allowlist. The artifact check confirms that no `KUBE_READY_EGRESS` chain remains | Gap → REQ-007 |

## Scope

- In scope: read-only validators (`security/`, `network/`, `storage/`, `tools/node-readiness-attest.sh`,
  `nixos/preflight.sh`, `packer/scripts/07-check-tuning.sh`, `09-k8s-node-preflight.sh`);
  CI negative tests; a static mutation guard; `docs/host-security-baseline.md`; `docs/evidence-contracts.md`.
- Affected consumers: anyone gating on `kube-ready-security/v1`, `kube-ready-network/v1`,
  `kube-ready-storage/v1` or `kube-ready-readiness/v1` status, including `tools/kube-ready-contracts.sh`
  and the OpenForge status publisher.

## Non-goals

- No firewall rule generation, enabling, flushing or port opening on any image. Rocky's existing
  ssh-only `firewalld` stays unchanged.
- No SELinux or AppArmor mode toggling, except the existing Rocky enforcing-preservation and the
  NixOS AppArmor enablement decided in D5 (Q2, 2026-09-24) — see REQ-004 and T-022.
- No CNI, Cilium Host Firewall or NetworkPolicy work. That belongs to the cluster/installer
  repositories (see narwhal#190, kubemetal#74).
- No change to `.agents/skills/kube-ready-box-build-validation/`. #47 is working there.
- No containerd installation into the base box.

## Requirements

- `REQ-001`: The network validator reports the owning firewall **provider**
  (`firewalld`/`ufw`/`nftables`/`none`/`external`) separately from the packet-filter backend. A
  manager that is present is never masked by the `nft` binary.
- `REQ-002`: Every firewall check result has a non-empty, enumerated detail that separates
  *inactive*, *could not read* (privilege/tooling) and *empty ruleset*. This includes the PR #53
  `status-unavailable` case.
- `REQ-003`: AppArmor-native hosts: *enabled* → `PASS`; *kernel-capable but disabled* → `FAIL`;
  *cannot determine* → `UNKNOWN <reason>`. SELinux-native hosts keep `Enforcing` → `PASS` and
  `Permissive`/`Disabled`/drift → `FAIL`. No validator in scope may emit `PASS` for a disabled or
  permissive LSM. The kernel LSM stack is recorded. This classification is unconditional and does
  not vary by `KUBE_READY_SECURITY_PROFILE` or any other input (**D4**, decided 2026-09-24): there
  is no `standard`-profile fallback to `UNKNOWN` for a disabled or permissive LSM on a capable
  kernel.
- `REQ-004`: The LSM model is chosen by OS family (`ID`, then `ID_LIKE`) using this package's
  matrix. `nixos` and unknown families are classified explicitly, never defaulted to healthy.
  NixOS is AppArmor-native (**D5**, decided 2026-09-24): the image enables
  `security.apparmor.enable = true`, and the NixOS branch is classified by the same REQ-003 rule
  as Ubuntu (enabled → `PASS`, disabled → `FAIL`), not carried as a permanent exception.
- `REQ-005`: seccomp filter-mode support is verified at node level, and missing support on a known
  kernel is `FAIL`. Effective `RuntimeDefault` stays at the pod-level sandbox path and is linked
  from the host evidence.
- `REQ-006`: Every classification introduced or changed by REQ-001..005 has a deterministic allow
  case and a deny case exercised in CI. Paths CI cannot reach (Rocky SELinux, `ufw` when `nft`
  exists) have recorded container/VM evidence instead of a silent gap.
- `REQ-007`: A static guard fails `make lint`/CI when `iptables|nft|ufw|firewall-cmd|setenforce|
  aa-disable|systemctl (stop|disable) apparmor|apparmor=0|selinux=0` mutation forms appear outside
  an allowlist. The Ubuntu/Rocky artifact check asserts that no `KUBE_READY_EGRESS` chain remains.
- `REQ-008`: `docs/host-security-baseline.md` defines the installer hand-off. It covers what the
  image guarantees, Rocky's default-deny inbound, the containerd LSM integration the installer must
  configure, custom AppArmor profile distribution, workload-scoped `seLinuxOptions`, the evidence
  the installer should gate on, and rollback expectations.
- `REQ-009`: Exceptions (for example a host that cannot run a firewall) are recorded as evidence
  with owner, reason and expiry, not as `PASS`. NixOS without an enabled LSM is no longer an
  eligible exception (**D5**, decided 2026-09-24): see REQ-004.
- `REQ-010`: The evidence schema change is backward-compatible or versioned (Q3). Downstream
  consumers are told before any `UNKNOWN`→`FAIL` reclassification ships.

## Acceptance scenarios

Each enforcement or classification change has an **allow** case and a **deny** case.

### `AC-001`: firewall provider named correctly (REQ-001)
- Allow: Given a Rocky 9 box with `firewalld` active, when the network validator runs, then
  `firewall_provider=PASS firewalld` and `firewall_state=PASS running`, not `nftables`.
- Allow: Given Ubuntu with `ufw` enabled and `nft` present, then `firewall_provider=PASS ufw`.
- Deny: Given Rocky with `firewalld` stopped, then `firewall_state=UNKNOWN inactive`, and the check
  is never `PASS`.

### `AC-002`: firewall state is actionable (REQ-002)
- Allow: Given root and a non-empty nft ruleset, then `firewall_rules=PASS present`.
- Deny: Given an unprivileged run, then the detail is `permission-denied`/`status-unavailable`, never
  empty and never `empty`. Given `ufw` inactive, then `UNKNOWN inactive` (PR #53 table unchanged).

### `AC-003`: AppArmor truthfulness (REQ-003, REQ-004, D4, D5)
- Allow: Given an Ubuntu box booted normally, then `apparmor=PASS enabled`, `mac_backend=PASS AppArmor`,
  and `lsm_stack` contains `apparmor`.
- Deny: Given an Ubuntu kernel booted with `apparmor=0` (VM) or a fixture reporting disabled, then
  `apparmor=FAIL disabled`, and every other in-scope validator (storage, attest, preflight) is
  non-PASS for MAC. This holds regardless of `KUBE_READY_SECURITY_PROFILE` (D4) — there is no
  `standard`-profile run that reports `UNKNOWN` or `PASS` instead.
- Deny: Given a container without `/sys/kernel/security`, then `UNKNOWN <reason>`, not `FAIL` and
  not `PASS`.
- Allow: Given a NixOS box built with `security.apparmor.enable = true` (D5), then
  `apparmor=PASS enabled`, `mac_backend=PASS AppArmor`, and `lsm_stack` contains `apparmor` — the
  same classification path as Ubuntu, with no NixOS-specific exception branch.
- Deny: Given a NixOS box without AppArmor enabled (the pre-D5 default, or a build regression),
  then `apparmor=FAIL disabled` and `mac_backend=FAIL` — never `UNKNOWN` and never a recorded
  exception.

### `AC-004`: SELinux preserved (REQ-003, REQ-004, D4)
- Allow: Given Rocky 9 as built, then `selinux=PASS Enforcing` and `selinux_policy` shows
  `config=enforcing runtime=Enforcing`.
- Deny: Given `setenforce 0` on a disposable Rocky VM, then `selinux=FAIL Permissive` in the security,
  storage and Rocky preflight validators, regardless of `KUBE_READY_SECURITY_PROFILE` (D4). Given an
  `almalinux`/`fedora` `os-release` fixture, then the SELinux branch runs (not `mac_backend UNKNOWN`).

### `AC-005`: seccomp prerequisites (REQ-005)
- Allow: Given a GitHub Ubuntu runner, then `seccomp=PASS` and `seccomp_filter=PASS` with an
  `actions_avail` detail.
- Deny: Given a fixture or kernel without filter mode, then `seccomp_filter=FAIL`. Given the pod
  path, `sandbox/verify-sandbox-evidence.sh` still proves `Seccomp: 2` for a `RuntimeDefault` pod.

### `AC-006`: no blind mutation (REQ-007)
- Allow: Given the current tree, then the guard passes; the only matches are the allowlisted
  `rocky-tuning.sh`, `ks.cfg`, `00-egress-restrict.sh` and `99-cleanup.sh`.
- Deny: Given a test commit that adds `ufw enable` or `setenforce 0` to any other script, then
  `make lint` and CI fail and name the file and line.

### `AC-007`: hand-off contract (REQ-008, REQ-009)
- Given an installer author reading `docs/host-security-baseline.md`, then they can find the
  guarantee, their obligation, a verification command and a rollback expectation for each of:
  host firewall/ports (including Rocky default-deny), containerd AppArmor/SELinux integration,
  custom AppArmor profiles, `seLinuxOptions`, seccomp `RuntimeDefault`. Each exception has owner,
  reason and expiry.

## Architecture and decisions

- Relevant: OpenForge ADR-0014 (Kubernetes Zero Trust baseline); `docs/evidence-contracts.md`
  ("Enforcement provider boundary"); `security/README.md` (`declared→supported→loaded→effective→verified`).
- ADR threshold result: **required**. The change alters security-evidence semantics
  (`UNKNOWN`→`FAIL`) and fixes a trust/ownership boundary: the installer, not the image, owns
  firewall and runtime LSM integration. kube-ready-box has no `docs/adr/` yet (Q6).
- Decisions proposed for acceptance:
  - **D1**: Observe and preserve, and never generate firewall policy. Cost: Ubuntu and NixOS ship
    with no active host firewall. Escape hatch: C-03 re-review date.
  - **D2**: A disabled LSM on a native-capable kernel is `FAIL`, not `UNKNOWN`. Cost: some existing
    runs turn red. Escape hatch: a schema bump (Q3) or a recorded REQ-009 exception; **no profile
    switch** — D4 (2026-09-24) forecloses that option and makes this unconditional.
  - **D3**: Paths CI cannot reach are proven with recorded container/VM evidence rather than
    test-only hooks in production scripts. This follows the PR #53 precedent. The alternative is
    PATH-shim fixtures (Q4).
  - **D4** (decided 2026-09-24, resolves Q1): A disabled LSM (AppArmor not enabled, or SELinux
    permissive/disabled) is `FAIL` **always**, regardless of `KUBE_READY_SECURITY_PROFILE` or any
    other input. Reason: gating this on a profile would let a `standard` run mask an unenforced
    MAC on a capable kernel, reproducing the false-green problem #44 exists to fix. Cost: existing
    green runs on hosts with a disabled/permissive LSM turn `FAIL` immediately, with no `standard`
    fallback to `UNKNOWN` (see Rollout, rollback and recovery — migration note). Escape hatch: no
    profile switch; only a recorded, time-bound REQ-009 exception (owner, reason, expiry) or
    reverting the reclassification commit, which stays separate per rollout order.
  - **D5** (decided 2026-09-24, resolves Q2): NixOS images enable `security.apparmor.enable = true`
    rather than carrying a permanent C-09 exception. Reason: AppArmor is available on NixOS, so the
    same LSM rule (REQ-004) applied to Ubuntu/Rocky applies to NixOS — enable and enforce, don't
    except. Cost: this is an enforcement change to the shipped NixOS image (not reporting-only), so
    it carries its own build/compatibility risk (module availability, hardened-kernel interaction)
    and needs allow/deny/rollback evidence like REQ-003's reclassification (T-022). Escape hatch:
    revert the NixOS-enablement commit, kept separate from the reporting-only changes; no permanent
    exception route remains for C-09 afterward.
- Alternatives rejected: shipping a "Kubernetes ports" firewall profile in the image (breaks unknown
  CNI topologies, and #44 forbids it explicitly); disabling SELinux on Rocky for runtime
  compatibility (forbidden by #44 and OpenForge #77 §6).

## Change impact

| Area | Impact / evidence needed |
|---|---|
| Source / API / command | Validator scripts listed in Scope; new check IDs (`firewall_provider`, `lsm_stack`, `seccomp_filter`); reclassified statuses (C-05, C-06) |
| Dependencies / lockfiles | N/A — no new packages; reads `/sys`, `/proc` and existing CLIs only |
| Runtime / toolchain | N/A — bash + python3 as today |
| CI / CD | `validate.yml` `readiness-negative-tests` gains allow/deny cases; `make lint` gains the mutation guard |
| Release / packaging | Box contents are unchanged. Evidence output changes, so the release notes must call out the reclassification |
| Generated output | Evidence JSON under `kube-ready-*/v1` (or v2, per Q3) |
| Security / supply chain | Tightens evidence truthfulness. No new executable inputs |
| Offline / air-gap | N/A — validators need no network |
| Documentation / operations | `docs/host-security-baseline.md`, `docs/evidence-contracts.md`, `security/README.md`, `rocky/README.md` (default-deny note) |
| Portfolio / downstream repositories | Installers consuming kube-ready-box (narwhal, kubemetal); OpenForge #77 feedback on reusable gaps (C-01 provider-vs-backend, C-02 detail vocabulary) |

## Verification plan

| Acceptance ID | Verification method | Environment | Expected evidence |
|---|---|---|---|
| AC-001 | `bash network/node-network-readiness.sh \| jq '.checks[]\|select(.id\|test("firewall"))'` | Rocky 9 Vagrant box (firewalld up/stopped); `ubuntu:24.04` container with `ufw` + `nft` (`--privileged`) | JSON before/after, recorded in PR |
| AC-002 | Same, unprivileged vs `--privileged` | `ubuntu:24.04` container (PR #53 method) and GitHub runner | Detail table as in PR #53 |
| AC-003 | `bash security/workload-security-check.sh`; storage/attest/preflight | GitHub Ubuntu runner (allow); Ubuntu Vagrant box booted `apparmor=0` (deny); NixOS build with `security.apparmor.enable = true` (allow, D5) and without it (deny, D5); plain container (UNKNOWN) | JSON per case |
| AC-004 | `getenforce; bash security/workload-security-check.sh; bash rocky/preflight.sh`, then `sudo setenforce 0` and rerun, then `sudo setenforce 1` | Disposable Rocky 9 VM only | JSON per case + restored `Enforcing` |
| AC-005 | Validator + `sandbox/verify-sandbox-evidence.sh` | Runner; `sandbox-enforcement-evidence.yml` cluster path | JSON + sandbox evidence link |
| AC-006 | `make lint` on the tree; the same on a throwaway commit that adds `ufw enable` | Local + CI | Pass, then fail naming file:line |
| AC-007 | Reviewer walkthrough against the REQ-008 checklist | Docs | Review comment |
| all | `shellcheck --severity=warning`, `bash -n`, `make lint`, `./packer/build.sh validate` | Local + CI | Clean |

Static checks (shellcheck/lint) are not runtime evidence. AC-001, AC-003 deny and AC-004 require a
real VM and will be recorded as such.

## Rollout, rollback and recovery

Every step is read-only with respect to host firewall and LSM state, except the explicit
disposable-VM toggles used as test fixtures.

| Change | Fail-closed behavior | Rollback trigger | Rollback / recovery |
|---|---|---|---|
| REQ-001/002 firewall reporting | An undeterminable provider/state is `UNKNOWN <reason>`, never `PASS` | A consumer breaks on a new check ID | `git revert`; IDs are additive, so old consumers ignore them |
| REQ-003/004 LSM reclassification | A disabled LSM becomes `FAIL` (**behavior change**, unconditional per D4 — no profile fallback) | Previously green release/CI runs turn red on hosts with a disabled or permissive LSM that were previously reported healthy. **Migration note**: any host or CI run that was `PASS`/`UNKNOWN` for MAC before this reclassification and has AppArmor disabled or SELinux permissive/disabled will `FAIL` after this ships; there is no profile input to opt back into the old behavior | Revert the reclassification commit (kept separate from the additive checks). The host is never touched |
| D5 NixOS AppArmor enablement | AppArmor is enabled at build time; the build should fail loudly if `security.apparmor.enable` cannot take effect, rather than shipping silently unenforced | AppArmor causes a boot or workload regression on a built NixOS box | Revert the enablement commit only (kept separate from the reporting-only REQ-003/004 changes). The NixOS image reverts to its pre-D5 state, which then `FAIL`s under REQ-003/004 with no exception route — call this out in the PR so it is not mistaken for a new regression |
| REQ-005 seccomp filter | Missing filter mode on a known kernel → `FAIL` | False FAIL on a supported kernel | Revert; the fixture reproduces it |
| REQ-007 mutation guard | Unknown mutation → CI fail | Legitimate new scoped mutation | Add it to the reviewed allowlist in the same PR, with justification |
| AC-004 test toggle | Disposable VM only | `setenforce 1` fails | Destroy the VM (`vagrant destroy -f`). Never run on a shared host |
| C-03/C-12 (no firewall/CNI mutation) | Nothing is mutated | — | Installer-owned. The hand-off requires the installer to keep an out-of-band console, stage audit→enforce, and snapshot the ruleset before changing it (OpenForge #77 §2) |

Rollout order: (1) additive checks and docs; (2) CI allow/deny tests; (3) the `UNKNOWN`→`FAIL`
reclassification in its own PR, announced to downstream consumers (REQ-010).

## Evidence and durable synchronization

- Evidence: validator JSON attached to each implementation PR. VM/container evidence goes under
  `release-evidence/` or in the PR body, with environment, command and outcome, failures included.
- Durable regression controls: the CI negative tests (REQ-006) and the mutation guard (REQ-007).
- Docs: `docs/host-security-baseline.md` (distro/LSM matrix, hand-off),
  `docs/evidence-contracts.md`, `security/README.md`, `rocky/README.md`.
- ADR: new host-security ownership ADR (location per Q6). Feed C-01/C-02 back to OpenForge #77.

## Relationship to in-flight work

- **PR #53** (`fix/44-ufw-status-unavailable-evidence`, awaiting human review) implements part of
  REQ-002 (`ufw` empty stdout → `status-unavailable`). This package assumes it merges first and does
  not modify that branch. If #53 is rejected, T-011 absorbs the same case.
- **#47** (build-validation skill) is unrelated and untouched.
- `2a2c917` shipped #44 docs and `ufw` detection without a package. It is treated as the pre-change
  baseline here, not as accepted scope.

## Review record

- Accepted scope/requirements: — (pending)
- Decisions accepted by reviewer: **D4** (Q1) and **D5** (Q2), dated 2026-09-24 — see Architecture
  and decisions. Package acceptance as a whole remains pending; Q3–Q7 are still open.
- Material changes after acceptance and re-review: —
- Open questions for the reviewer:
  - **Q1 — DECIDED (D4, 2026-09-24)**: A disabled LSM (AppArmor not enabled, or SELinux
    permissive/disabled) is `FAIL` always, regardless of `KUBE_READY_SECURITY_PROFILE`. See D4.
  - **Q2 — DECIDED (D5, 2026-09-24)**: NixOS images enable `security.apparmor.enable = true`;
    C-09 is not a permanent exception. See D5.
  - **Q3**: Is reclassifying existing check IDs a `kube-ready-security/v1` compatible change, or does
    it need `v2`?
  - **Q4**: For unreachable deny paths, accept PATH-shim/`os-release` fixtures in CI, or keep the PR #53
    policy of recorded container/VM evidence only?
  - **Q5**: Is "ssh-only `firewalld`" the intended Rocky default (production-aligned default-deny), or
    was it incidental? Either way it stays unchanged here; the question is only how the hand-off
    describes it.
  - **Q6**: Where should the ADR live? The repo has no `docs/adr/`; alternatively, an OpenForge-side ADR amendment.
  - **Q7**: Merge this package as `docs/changes/…` or keep it PR-only per OpenForge's "short-lived" guidance?
