# Change: Host security baseline — firewall, AppArmor, SELinux and seccomp evidence (#44)

- Change class: `D` — security boundary: it changes which host-security states the shipped
  images and their validators report as healthy, and it fixes the firewall/LSM ownership
  boundary between kube-ready-box and cluster installers.
- Owner: @dasomel
- Related issue: #44 (source of truth: dasomel/openforge#77, `docs/kubernetes-zero-trust-security-baseline.md`)
- Status: `Accepted` — implementation proceeds per `TASKS.md`; this package itself contains no implementation
- Accepted by / date: @dasomel / 2026-09-24 (revision `41582e4`)

This package follows the OpenForge short-lived Change Package lifecycle
(`docs/change-management.md` in dasomel/openforge). It is a working artifact for review.
**Decided (D10, 2026-09-24, resolves Q7): the package stays in the PR**, pinned by revision —
it is not merged as a durable `docs/changes/...` doc — and implementation PRs link back to this
revision instead of duplicating it.

## Problem

OpenForge #77 sets the `production` profile to: seccomp `RuntimeDefault` required; AppArmor or
SELinux **enforcing where supported**; host OS firewall **required where the host is managed**;
and no blind firewall mutation on an unknown topology.

Part of #44 has already landed on `main` (`2a2c917`: `docs/host-security-baseline.md` and `ufw`
detection). That work was recorded as reviewed only. PR #53 fixes one empty-evidence defect in it
and has since merged (`d561d76`). The inventory below shows that the rest of the evidence is not
yet fit to gate a production profile:

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
| Ubuntu 24.04 (default) / 26.04 | `packer/{virtualbox,vmware}-{amd64,arm64}.pkr.hcl`, ISO map `packer/plugins.pkr.hcl:85-100` | amd64+arm64 / VirtualBox+VMware | **AppArmor**: kernel/AppArmor packages kept at latest via `apt-get install --only-upgrade` (not version-pinned) in `packer/scripts/01-base.sh:66-74`; `apparmor-utils` installed unversioned by `03-os-packages.sh:49` | No policy from kube-ready-box. The distro default is `ufw` installed but inactive (**to verify on a built box**, T-002) |
| Rocky 9 | `packer/rocky-{virtualbox,vmware}-arm64.pkr.hcl`, `packer/http/rocky-9-{ext4,xfs}/ks.cfg` | arm64 / VirtualBox+VMware | **SELinux `Enforcing`**: `ks.cfg:11` and `packer/scripts/rocky-tuning.sh:13-22` | **`firewalld` active with SSH allowed, preserved intentionally** (**D8**, 2026-09-24): `ks.cfg:12` and `rocky-tuning.sh:28-37` add the `ssh` service but do not remove or verify other default zone services/ports, so exclusivity to SSH is not proven — see T-002 |
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
| C-05 | AppArmor enabled on AppArmor-native images | `security/workload-security-check.sh:8-16`: `mac_backend PASS AppArmor` is emitted even when AppArmor is disabled, and a disabled AppArmor is only `UNKNOWN`. Same pattern in `packer/scripts/07-check-tuning.sh:186-193` and `09-k8s-node-preflight.sh:71-73`. The kernel LSM stack (`/sys/kernel/security/lsm`) is never read | Enabled → `PASS`. Tooling cannot tell → `UNKNOWN <reason>`. **Enabled-capable kernel but AppArmor disabled → `FAIL`**, unconditionally regardless of `KUBE_READY_SECURITY_PROFILE` or any other profile (**D4**) — there is no production-profile-only carve-out. Record the LSM stack | Gap → REQ-003 |
| C-06 | No false-green in secondary validators | `storage/node-storage-readiness.sh:39-45`: `PASS apparmor:disabled` and `PASS selinux:Permissive/Disabled`. `nixos/preflight.sh:82` and `tools/node-readiness-attest.sh:60` treat the existence of `/sys/module/apparmor` as "loaded", even when AppArmor is disabled at boot. **The Rust verifier has the same false-green**: `rust/kube-ready-verifier/src/checks/security_time.rs:21` reports `apparmor=PASS` from `/sys/module/apparmor` directory existence alone, with no `aa-status`-equivalent enforcement probe, so it can disagree with the (fixed) bash check on the same host | Same classification as C-05. If the check stays informational, the ID is renamed so it cannot be read as a policy PASS. The Rust check gets the same fix and the same deny fixture as `T-021`, alongside it, so bash and Rust agree | Gap → REQ-003 |
| C-07 | SELinux `Enforcing` on SELinux-native images | Correct in `workload-security-check.sh:11-15` and `rocky/preflight.sh:11-32` for the `config=enforcing, runtime downgraded` drift direction. **Not correct for the reverse drift**: the `selinux_policy` check (`workload-security-check.sh:54`) only flags `config=enforcing` combined with a permissive/disabled runtime; `config=permissive, runtime=Enforcing` still passes (`selinux_policy PASS`, reproduced), so a config change that will lose enforcement on next boot is not caught. A runtime-query failure (`getenforce` erroring) is also not distinguished from a clean state. The family match is limited to `rocky`/`rhel` | Keep the existing direction. Also flag `config != enforcing` while `runtime=Enforcing` (reverse drift) as `FAIL`, and a `getenforce` failure as `UNKNOWN <reason>`, never `PASS`. Widen the family detection to `ID_LIKE` (alma, fedora, centos) | Gap (partial) → REQ-004; reverse-drift and query-failure cases added to `AC-004` deny |
| C-08 | OS-family classification | Only `ubuntu`, `rocky` and `rhel` are recognized (`workload-security-check.sh:8-16`). `debian` and `nixos` → `mac_backend UNKNOWN` | Explicit mapping, with NixOS classified on purpose (see C-09) | Gap → REQ-004 |
| C-09 | NixOS LSM | No LSM is enabled. The validators report it as UNKNOWN or as a misleading "loaded" (C-06) | **Decided (D5, 2026-09-24): enable `security.apparmor.enable = true`.** Enabled → `PASS` under the same REQ-003 rule as Ubuntu; no exception is recorded for this state | Gap → REQ-003, REQ-004. Enablement is an enforcement change, not reporting-only; needs its own allow/deny/rollback evidence (T-022) |
| C-10 | seccomp node prerequisite | `workload-security-check.sh`: `seccomp` checks only for the `Seccomp:` line; `seccomp_capability` lists `actions_avail` | Also assert filter mode (`CONFIG_SECCOMP_FILTER`: the `Seccomp_filters:` field or `actions_avail` contains `errno` and `kill_process`). Missing → `FAIL` when the kernel is known | Gap → REQ-005 |
| C-11 | seccomp `RuntimeDefault` **effective** | Covered only by the pod-level path in `sandbox/verify-sandbox-evidence.sh:74-92`, which needs a cluster | Keep at pod level and link from the host evidence. A node-only image cannot prove it (`security/README.md`) | **N/A at image level.** Covered by the cluster path, per the existing `declared→…→verified` contract |
| C-12 | Runtime LSM integration (containerd AppArmor default profile, `enable_selinux`, `container-selinux`) | containerd is not in the Ubuntu/Rocky base box (`packer/scripts/07-check-tuning.sh:234`). **NixOS is the exception**: `nixos/configuration.nix:142-143` already sets `virtualisation.containerd.enable = true` and `virtualisation.docker.enable = true`, so the image-level N/A premise does not hold there | Check it when a runtime is present. **NixOS: containerd/Docker AppArmor integration is verified as part of D5 (T-022), not deferred to the installer.** Otherwise it is an installer obligation in the hand-off contract | **N/A at image level for Ubuntu/Rocky** (no runtime shipped). **In scope for NixOS** via D5/T-022. Installer obligation elsewhere (REQ-008); re-evaluate for Ubuntu/Rocky if they ever ship containerd |
| C-13 | Custom AppArmor profile distribution / `seLinuxOptions` | Documented in `docs/host-security-baseline.md` ("Cluster-installer hand-off") | Keep the doc. Add the verification recipe (`aa-status --json` profile name present on every eligible node) | Docs → REQ-008 |
| C-14 | Deterministic allow/deny tests | CI asserts only `privileged_workload` PASS/FAIL and `firewall_backend` non-FAIL (`.github/workflows/validate.yml:416-448`) | Every new classification has a PASS case and a FAIL/UNKNOWN case in CI | Gap → REQ-006 |
| C-15 | No blind host mutation | The mutations that exist are all scoped: `rocky-tuning.sh` (Rocky build), `ks.cfg`, build-time egress `00-egress-restrict.sh` (opt-in, `plugins.pkr.hcl:138-147`) removed by `99-cleanup.sh:14-16` | A static guard fails CI when a firewall or LSM mutation command appears outside an allowlist. The artifact check confirms that no `KUBE_READY_EGRESS` chain remains | Gap → REQ-007 |

## Scope

- In scope: read-only validators (`security/`, `network/`, `storage/`, `tools/node-readiness-attest.sh`,
  `nixos/preflight.sh`, `packer/scripts/07-check-tuning.sh`, `09-k8s-node-preflight.sh`,
  `rust/kube-ready-verifier/src/checks/security_time.rs`, `sandbox/verify-sandbox-evidence.sh` regex only);
  CI negative tests; a static mutation guard; `docs/host-security-baseline.md`; `docs/evidence-contracts.md`.
- In scope, **not read-only** (D5): `nixos/configuration.nix` enables `security.apparmor.enable = true`,
  which changes shipped NixOS image behavior. It lands in its own PR (T-022) with boot, runtime and
  rollback evidence.
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
  aa-disable|systemctl (stop|disable) apparmor|apparmor=0|selinux=0` mutation forms appear, matched
  **per line/form, not by exempting an entire allowlisted file** — an allowlisted script
  (`rocky-tuning.sh`, `ks.cfg`) may still contain a mutation the guard should flag if it is not one
  of the specific allowed lines. The guard also covers declarative NixOS settings that disable
  enforcement (a `security.apparmor.enable = false`/`networking.firewall.enable` toggle in
  `nixos/configuration.nix`; the existing `:106` firewall-disable line stays allowlisted as the
  documented D1 default). The Ubuntu/Rocky artifact check asserts that no `KUBE_READY_EGRESS` chain
  remains.
- `REQ-008`: `docs/host-security-baseline.md` defines the installer hand-off. It covers what the
  image guarantees, Rocky's default-deny inbound, the containerd LSM integration the installer must
  configure, custom AppArmor profile distribution, workload-scoped `seLinuxOptions`, the evidence
  the installer should gate on, and rollback expectations.
- `REQ-009`: Exceptions (for example a host that cannot run a firewall) are recorded as evidence
  with owner, reason and expiry, not as `PASS`. An exception missing a required field
  (owner/reason/expiry) or past its expiry is treated as no exception: the underlying check reports
  its normal `FAIL`/`UNKNOWN`, never a suppressed `PASS`. NixOS without an enabled LSM is no longer
  an eligible exception (**D5**, decided 2026-09-24): see REQ-004.
- `REQ-010`: The evidence schema change is backward-compatible or versioned (**D6**, decided
  2026-09-24, resolves Q3). Downstream consumers are told before any `UNKNOWN`→`FAIL`
  reclassification ships.

## Acceptance scenarios

Each enforcement or classification change has an **allow** case and a **deny** case.

### `AC-001`: firewall provider named correctly (REQ-001)
- Allow: Given a Rocky 9 box with `firewalld` active, when the network validator runs, then
  `firewall_provider=PASS firewalld` and `firewall_state=PASS running`, not `nftables`.
- Allow: Given Ubuntu with `ufw` enabled and `nft` present, then `firewall_provider=PASS ufw`.
- Allow: Given both `firewalld` and `ufw` installed and active on the same host, then the validator
  names exactly one provider by a documented precedence rule, never both and never `nftables`.
- Deny: Given Rocky with `firewalld` stopped, then `firewall_state=UNKNOWN inactive`, and the check
  is never `PASS`.
- Deny: Given no `firewalld`/`ufw` manager active but an externally managed raw `nft` ruleset is
  active, then `firewall_provider=UNKNOWN external` with the ruleset detail, not misreported as a
  `nftables` PASS.
- Deny: Given no firewall manager and no active `nft` ruleset at all, then `firewall_provider=UNKNOWN none`.

### `AC-002`: firewall state is actionable (REQ-002)
- Allow: Given root and a non-empty nft ruleset, then `firewall_rules=PASS present`.
- Allow: Given root and a manager active with a deliberately empty ruleset, then the detail is a
  distinct `empty-ruleset` (a successful check of nothing), not folded into the same `UNKNOWN empty`
  bucket as a failed query.
- Deny: Given an unprivileged run, then the detail is `permission-denied`/`status-unavailable`, never
  empty and never `empty`. Given `ufw` inactive, then `UNKNOWN inactive` (PR #53 table unchanged).
- Deny: Given the firewall tool itself is not installed vs. installed but the query fails, then the
  two are distinguishable details (`tool-absent` vs `permission-denied`/`status-unavailable`), not
  collapsed into the same `UNKNOWN`.

### `AC-003`: AppArmor truthfulness (REQ-003, REQ-004, D4, D5)
- Allow: Given an Ubuntu box booted normally, then `apparmor=PASS enabled`, `mac_backend=PASS AppArmor`,
  and `lsm_stack` contains `apparmor`.
- Deny: Given an Ubuntu kernel booted with `apparmor=0` (VM) or a fixture reporting disabled, then
  `apparmor=FAIL disabled`, and every other in-scope validator (storage, attest, preflight) is
  non-PASS for MAC. This holds regardless of `KUBE_READY_SECURITY_PROFILE` (D4) — there is no
  `standard`-profile run that reports `UNKNOWN` or `PASS` instead.
- Deny: Given a container without `/sys/kernel/security` (securityfs absent), then `UNKNOWN <reason>`,
  not `FAIL` and not `PASS`. **Distinguish this from a confirmed-disabled state**: given securityfs
  absent but `/sys/module/apparmor/parameters/enabled` readable and `N`, then `apparmor=FAIL disabled`
  (confirmed disabled takes precedence over the generic securityfs-absent `UNKNOWN`, per D4/T-021).
- Allow: Given a NixOS box built with `security.apparmor.enable = true` (D5), then
  `apparmor=PASS enabled`, `mac_backend=PASS AppArmor`, and `lsm_stack` contains `apparmor` — the
  same classification path as Ubuntu, with no NixOS-specific exception branch.
- Deny: Given a NixOS box without AppArmor enabled (the pre-D5 default, or a build regression),
  then `apparmor=FAIL disabled` and `mac_backend=FAIL` — never `UNKNOWN` and never a recorded
  exception.

### `AC-004`: SELinux preserved (REQ-003, REQ-004, D4)
- Allow: Given Rocky 9 as built, then `selinux=PASS Enforcing` and `selinux_policy` shows
  `config=enforcing runtime=Enforcing`.
- Deny: Given `setenforce 0` on a disposable Rocky VM, then `selinux=FAIL Permissive` in the security
  and Rocky preflight validators, and `mac_backend=FAIL selinux:Permissive` in the storage validator
  (**the storage check ID is `mac_backend`, not `selinux`** — `storage/node-storage-readiness.sh:40`),
  regardless of `KUBE_READY_SECURITY_PROFILE` (D4). Given an `almalinux`/`fedora` `os-release`
  fixture, then the SELinux branch runs (not `mac_backend UNKNOWN`).
- Deny: Given `getenforce` reports `Disabled` (not only `Permissive`), then `selinux=FAIL Disabled`
  in all three validators (D4).
- Deny: Given the **reverse drift** (C-07) — `/etc/selinux/config` set to non-`enforcing` while the
  running kernel is still `Enforcing` — then `selinux_policy=FAIL`, not `PASS`, since enforcement is
  lost on the next boot. Given `getenforce` itself fails to run, then `selinux_policy=UNKNOWN <reason>`,
  never `PASS`.

### `AC-005`: seccomp prerequisites (REQ-005)
- Allow: Given a GitHub Ubuntu runner, then `seccomp=PASS` and `seccomp_filter=PASS` with an
  `actions_avail` detail.
- Deny: Given a fixture or kernel without filter mode, then `seccomp_filter=FAIL`. Given the pod
  path, `sandbox/verify-sandbox-evidence.sh` proves `Seccomp: 2` for a `RuntimeDefault` pod — **its
  current regex at `verify-sandbox-evidence.sh:92` (`Seccomp:[[:space:]]*[12]`) also accepts
  `Seccomp: 1` (filtering, not the enforced-default mode); tighten it to require `2`, with a deny
  case for a pod stuck at mode `1`** (see T-017).
- Deny: Given a kernel/container where seccomp state cannot be observed at all (no `Seccomp:` line
  in `/proc/self/status` and no `actions_avail`), then `seccomp`/`seccomp_capability`/`seccomp_filter`
  are `UNKNOWN <reason>`, never `PASS` or `FAIL`.

### `AC-006`: no blind mutation (REQ-007)
- Allow: Given the current tree, then the guard passes; the only matches are the allowlisted
  `rocky-tuning.sh`, `ks.cfg`, `00-egress-restrict.sh` and `99-cleanup.sh`.
- Allow: Given a read-only command (e.g. `getenforce`, `firewall-cmd --state`) in any script,
  allowlisted or not, then the guard does not flag it.
- Deny: Given a test commit that adds `ufw enable` or `setenforce 0` to any other script, then
  `make lint` and CI fail and name the file and line.
- Deny: Given `setenforce 0` inserted into an already-allowlisted file (e.g. `rocky-tuning.sh`)
  outside its documented enforcing-preservation lines, then the guard still fails it — the allowlist
  is per line/form, not per file.
- Deny: Given a build that leaves a residual `KUBE_READY_EGRESS` chain after `99-cleanup.sh`, then
  the artifact check fails and names the chain.

### `AC-007`: hand-off contract (REQ-008, REQ-009)
- Given an installer author reading `docs/host-security-baseline.md`, then they can find the
  guarantee, their obligation, a verification command and a rollback expectation for each of:
  host firewall/ports (including Rocky default-deny), containerd AppArmor/SELinux integration,
  custom AppArmor profiles, `seLinuxOptions`, seccomp `RuntimeDefault`. Each exception has owner,
  reason and expiry.
- Deny (REQ-009): Given a recorded exception with a missing field (owner/reason/expiry) or an
  expiry date in the past, then it is not honored — the check it would have suppressed reports its
  normal `FAIL`/`UNKNOWN` status.

### `AC-008`: consumers are told before reclassification (REQ-010, D6)
- Allow: Given the reclassification PR (T-020..T-023), then its description links the consumer list
  from T-004 and the notice, and `schema` stays `kube-ready-security/v1` with the same check IDs and
  field types.
- Deny: Given a reclassification PR without the T-004 consumer list or notice, or one that removes a
  check ID or changes a field type while keeping `v1`, then review rejects it (a removal or type
  change requires a schema bump per D6).

## Architecture and decisions

- Relevant: OpenForge ADR-0014 (Kubernetes Zero Trust baseline); `docs/evidence-contracts.md`
  ("Enforcement provider boundary"); `security/README.md` (`declared→supported→loaded→effective→verified`).
- ADR threshold result: **required**. The change alters security-evidence semantics
  (`UNKNOWN`→`FAIL`) and fixes a trust/ownership boundary: the installer, not the image, owns
  firewall and runtime LSM integration. kube-ready-box has no `docs/adr/` yet; **decided (D9,
  2026-09-24, resolves Q6): a new local `docs/adr/` is created**, covering D1–D10.
- Decisions proposed for acceptance:
  - **D1**: Observe and preserve, and never generate firewall policy. Cost: Ubuntu and NixOS ship
    with no active host firewall. Escape hatch: C-03 re-review date.
  - **D2**: A disabled LSM on a native-capable kernel is `FAIL`, not `UNKNOWN`. Cost: some existing
    runs turn red. Escape hatch: a recorded REQ-009 exception, kept structurally schema-compatible
    per D6 rather than a bump; **no profile switch** — D4 (2026-09-24) forecloses that option and
    makes this unconditional.
  - **D3**: Paths CI cannot reach are proven with recorded container/VM evidence rather than
    test-only hooks in production scripts. This follows the PR #53 precedent, now combined per D7
    with deterministic CI fixtures for classification logic.
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
  - **D6** (decided 2026-09-24, resolves Q3): Reclassifying existing check IDs is treated as
    `kube-ready-security/v1` **structurally** compatible — no schema/ID/type change — but not
    automatically behaviorally compatible. Reason: `tools/kube-ready-contracts.sh:23` only checks
    that each report's last line parses as JSON and passes it through, the status publisher does
    not pin an internal security schema, and Rust's `verify_evidence.rs:130` also validates JSON
    syntax only — so a `v2` bump is not structurally required; the risk is entirely in consumers
    reacting to a flipped status/exit code. Cost: downstream consumers must be notified and given a
    status/exit-code/ID regression test (REQ-010, T-004). Escape hatch: revert the reclassification
    commit; if an ID is ever deleted or its type changed (not just its value), reconsider a `v2`.
  - **D7** (decided 2026-09-24, resolves Q4): Unreachable deny paths (Rocky SELinux, `ufw` when
    `nft` exists) are proven with **both** a deterministic CI fixture (PATH shim, isolated
    `os-release`/`proc`/`sys` fixture) for the classification logic, and separate recorded VM/
    container evidence for actual enforcement. Reason: `.github/workflows/validate.yml:445`
    currently exercises only the `privileged_workload` mutation and no MAC deny case; a fixture
    makes classification regression-testable in every CI run, while only a real VM proves
    enforcement. Cost: fixtures must be kept in sync with the real check logic. Escape hatch: a path
    that stays genuinely unreachable even with a fixture is recorded as VM-only evidence (D3)
    instead; no production-check bypass input is added to reach it.
  - **D8** (decided 2026-09-24, resolves Q5): Rocky's firewall posture is described as "`firewalld`
    active with SSH allowed, preserved intentionally," not "ssh-only." Reason:
    `packer/scripts/rocky-tuning.sh:35` and the Kickstart only declare that the `ssh` service is
    added; neither removes or verifies other default zone services/ports, so exclusivity to SSH is
    not proven by the source. Cost: `T-002` is extended to capture runtime **and** permanent
    firewalld zone/service/port/rich-rule state as evidence. Escape hatch: the Rocky policy itself
    is unchanged; the wording can be tightened again once that evidence is captured.
  - **D9** (decided 2026-09-24, resolves Q6): The ADR is written in a new local `docs/adr/` in this
    repository. Reason: `docs/evidence-contracts.md` and `docs/host-security-baseline.md` already
    own the local contracts this change touches, so keeping D1–D10 and the accepted compatibility
    decisions next to the code they govern keeps them traceable. Cost: one additional short ADR
    file to maintain (T-042, now covering D1–D10, not only D1–D3). Escape hatch: cross-link an
    OpenForge-side ADR for any higher-level policy change; the local ADR stays the
    implementation-level record either way.
  - **D10** (decided 2026-09-24, resolves Q7): The package stays PR-only (this `CHANGE.md`/`TASKS.md`
    pair), pinned by revision, rather than merging as a durable `docs/changes/...` document. Reason:
    `AGENTS.md:113` leaves a versioned working artifact optional and `AGENTS.md:115` forbids a
    duplicate long-lived specification tree; accepted decisions and scope are absorbed into durable
    docs (`docs/host-security-baseline.md`, `docs/evidence-contracts.md`, the new ADR) at completion
    per the existing synchronization step, so nothing is lost when the PR closes. Cost: readers
    track the package by PR/revision rather than a stable doc path. Escape hatch: if tracking spans
    enough PRs to become unmanageable, merge a temporary package doc and fold it back into durable
    docs once implementation completes.
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
| Release / packaging | Ubuntu/Rocky box contents are unchanged. **The NixOS image is not**: D5 adds `security.apparmor.enable = true`, an enforcement change to the shipped image, verified per T-022 (boot, runtime/AppArmor integration, workload, rollback). Evidence output changes, so the release notes must call out both the reclassification and the NixOS enablement |
| Generated output | Evidence JSON under `kube-ready-*/v1`, kept structurally compatible per D6 |
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
disposable-VM toggles used as test fixtures **and the D5 NixOS AppArmor enablement, which is a
build-time change to the shipped NixOS image, not a reporting-only change** (see the D5 row below).

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

- Evidence: validator JSON attached to each implementation PR. Genuine release-run VM/container
  evidence goes under `release-evidence/`, with environment, command and outcome, failures included.
  **Deny/experiment evidence (deliberately-failing fixtures, e.g. the AC-003/AC-004 deny cases) is
  attached to the PR only, never written under `release-evidence/`** — `tools/openforge-project-status.sh:70`
  walks that directory and picks the newest `PASS`/`FAIL` JSON per capability without distinguishing
  a real release check from a deliberate failure experiment (see T-036).
- Durable regression controls: the CI negative tests (REQ-006) and the mutation guard (REQ-007).
- Docs: `docs/host-security-baseline.md` (distro/LSM matrix, hand-off),
  `docs/evidence-contracts.md`, `security/README.md`, `rocky/README.md`.
- ADR: new host-security ownership ADR in local `docs/adr/` (D9, resolves Q6), covering D1–D10.
  Feed C-01/C-02 back to OpenForge #77.

## Relationship to in-flight work

- **PR #53** (`fix/44-ufw-status-unavailable-evidence`, awaiting human review) implements part of
  REQ-002 (`ufw` empty stdout → `status-unavailable`). This package assumes it merges first and does
  not modify that branch. If #53 is rejected, T-011 absorbs the same case.
- **#47** (build-validation skill) is unrelated and untouched.
- `2a2c917` shipped #44 docs and `ufw` detection without a package. It is treated as the pre-change
  baseline here, not as accepted scope.

## Review record

- Accepted scope/requirements: the package as a whole — Scope, REQ-001..010, AC-001..008 and
  D1–D10 — accepted by @dasomel on 2026-09-24 at revision `41582e4`.
- Decisions accepted by reviewer: **D4** (Q1), **D5** (Q2), **D6** (Q3), **D7** (Q4), **D8** (Q5),
  **D9** (Q6) and **D10** (Q7), all dated 2026-09-24 — see Architecture and decisions. Package
  accepted as a whole on 2026-09-24 (above).
- Material changes after acceptance and re-review: —
- Open questions for the reviewer:
  - **Q1 — DECIDED (D4, 2026-09-24)**: A disabled LSM (AppArmor not enabled, or SELinux
    permissive/disabled) is `FAIL` always, regardless of `KUBE_READY_SECURITY_PROFILE`. See D4.
  - **Q2 — DECIDED (D5, 2026-09-24)**: NixOS images enable `security.apparmor.enable = true`;
    C-09 is not a permanent exception. See D5.
  - **Q3 — DECIDED (D6, 2026-09-24)**: Reclassifying existing check IDs stays structurally
    `kube-ready-security/v1` compatible; behavioral compatibility is handled by consumer notice and
    regression tests, not a schema bump. See D6.
  - **Q4 — DECIDED (D7, 2026-09-24)**: Unreachable deny paths get both deterministic CI fixture
    coverage and separate recorded real VM/container evidence for enforcement. See D7.
  - **Q5 — DECIDED (D8, 2026-09-24)**: Described as "`firewalld` active with SSH allowed, preserved
    intentionally"; the policy is unchanged and exclusivity to SSH is not claimed. See D8.
  - **Q6 — DECIDED (D9, 2026-09-24)**: The ADR lives in a new local `docs/adr/`, covering D1–D10.
    See D9.
  - **Q7 — DECIDED (D10, 2026-09-24)**: The package stays PR-only, pinned by revision; it is not
    merged as a durable `docs/changes/...` doc. See D10.
