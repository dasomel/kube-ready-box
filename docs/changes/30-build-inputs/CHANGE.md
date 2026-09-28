# Change: Investigate immutable and offline release inputs for kube-ready-box (#30)

- Change class: `C`
- Owner: `dasomel`
- Related issue: [#30](https://github.com/dasomel/kube-ready-box/issues/30)
- Status: `Draft — investigation package; awaiting maintainer acceptance`
- Accepted by / date: pending

## Problem

The repository already pins base-image checksums and Packer plugin versions, verifies selected downloaded tools, rejects new floating downloads, and has an opt-in build-egress mechanism. The remaining issue requirements are still material release gaps: apt package versions change over time; the egress option is opt-in and its real-build evidence covers only Ubuntu 26.04/ext4 ARM64 on VirtualBox and VMware; offline bundling does not yet prove that Packer consumes only approved inputs; guest SBOM artifacts record installed packages and source/build provenance fields, but do not inventory the full build input closure or directly bind the final box digest; dependency cooling and compromised-input quarantine/recovery are undefined; negative substitution coverage is limited.

The current evidence record also contradicts itself: the VMware real-build section records a successful run, while an earlier paragraph and the final gap list still say VMware or any real Packer egress build is unverified. This proposal includes a small documentation correction before implementation planning is accepted.

## Intent

This package is limited to reconciling evidence, mapping trust boundaries, and producing separately reviewable implementation proposals. It does not authorize changes to package sources, build network policy, release gates, artifact formats, or dependency defaults. The eventual #30 outcome may require multiple implementation packages; #30 stays open until its issue criteria are met.

## Scope

- In scope for this package: correct current evidence; map build phases and external inputs; identify enforcement and verification boundaries; document decisions and split follow-up Class C packages for package reproducibility, egress, and offline bundle/provenance/revocation.
- Not authorized by this package: implementation across Ubuntu/Rocky/NixOS, changing apt repositories or package resolution, enforcing new network policy, changing release defaults/gates, or defining operational cooling/quarantine policy without named owners.
- Affected users/systems: maintainers choosing follow-up package boundaries and owners. Implementation packages may affect builders, CI, release operators, and evidence consumers.
- Existing verified controls remain in place: exact ISO checksums, exact Packer plugin versions, checksummed dool/yq inputs, the unpinned-input guard, egress mechanism tests, and selected live Packer egress builds.

## Proposed follow-up boundaries and issue traceability

Owners are pending maintainer assignment. Each follow-up is Class C and needs its own accepted Change Package before implementation.

| Follow-up package | #30 requirements / acceptance covered | Boundary and decisions still required |
|---|---|---|
| Immutable inputs and package reproducibility | Inventory, immutable versions, signatures/checksums, mutable-input guard, package manifests; negative substitution tests for representative packages/binaries, ISO checksums, and Packer plugins | Ubuntu/Rocky/Nix/host/CI inventory; repository snapshot and full dependency closure; historical package retention/security-update policy; expand guard scope beyond its current scan paths; cooling only if an operational owner and exception flow are accepted. |
| Build-egress enforcement | Restrict arbitrary egress; negative unexpected-network test | Start with currently exercised Ubuntu guest provisioning; decide how firewall bootstrap packages are trusted/provided before enforcement. Also decide IPv6, DNS tunneling, redirects/CDNs, local Packer traffic, installer, Rocky support, and required real-build matrix before any mandatory/default change. |
| Offline bundle, provenance, quarantine and recovery | Build-input SBOM/evidence chain, source→build→manifest→digest→artifact, approved offline build, fail-closed missing/unverified inputs, quarantine and last-known-good recovery | Define independently authenticated approval/revocation data, full bundle closure and consumers, physical no-network proof, build and promotion deny checks, and authorized non-revoked last-known-good selection. |

The original issue's cooling criterion says “where practical”; it is not a mandatory gate in this investigation proposal unless the maintainer accepts a named owner and audited exception process. A completion decision for #30 requires evidence from all accepted follow-up packages; this investigation package alone cannot close it.

## Non-goals

- Runtime package installation or runtime vulnerability scanning on deployed nodes.
- Replacing OS package signing with project-maintained checksums when the signed repository metadata already provides the appropriate trust boundary.
- Broadly changing every input or enabling a new release default before the corresponding accepted task and verification matrix are complete.
- Replacing box promotion rollback (#8); a follow-up package will address build-input quarantine and last-known-good recovery separately from artifact rollback.
- Treating a successful egress test in one provider/architecture as proof for other build targets.

## Requirements

- `REQ-001` — Correct documented egress-build evidence against issue comments and retained logs; distinguish historical status from current coverage and list remaining target combinations.
- `REQ-002` — Map release phases and external inputs, including host Packer/plugin fetch, OS installer, guest provisioning, and Nix fetch. Record current enforcement/evidence and inspect the firewall bootstrap interval, IPv4/IPv6, DNS transport/tunneling, redirects/CDNs, and local builder traffic before proposing egress criteria.
- `REQ-003` — Decompose issue requirements into independently reviewable follow-up packages for immutable/package inputs, egress controls, and offline bundle plus provenance/quarantine/recovery. Each boundary records the owner as assigned or explicitly pending, target/phase, assumptions, acceptance tests, and dependencies.
- `REQ-004` — Evaluate apt reproducibility against full transitive resolution, installer-phase inputs, signed metadata, clean-builder repeatability, historical availability, security updates, and missing-package failure. Do not prescribe direct package pins without proving closure availability.
- `REQ-005` — Define offline bundle trust and consumption requirements: approval manifest authenticated independently from bundle-generated checksums; full dependency closure and consumers; clean build with network physically unavailable. Self-checksum verification alone is insufficient.
- `REQ-006` — Define provenance/SBOM linkage and distinguish guest inventory from build-input evidence; make format, signing, retention, and consumers decisions for a follow-up package.
- `REQ-007` — Keep cooling optional until an owner, clock-start event, review rule, and security-update exception are named. A follow-up must model revocation as an authenticated deny decision checked at build and promotion, and define an authorized last-known-good replacement path; cache/bundle deletion is best effort.
- `REQ-008` — Separate negative outcomes: input/build verification exits non-zero; the release path does not accept or publish rejected artifacts. Local artifact existence alone is not a release-gate failure.

## Acceptance scenarios

### `AC-001` — Evidence and build boundaries are accurate

- Covers: `REQ-001`, `REQ-002`
- Given the current build evidence and supported target list, the docs state verified real-build coverage accurately and an inventory maps external inputs and enforcement points across host, installer, provisioning, and Nix phases, including known network bypass considerations.

### `AC-002` — Follow-up packages are independently reviewable

- Covers: `REQ-003`–`REQ-008`
- Given the issue requirements and current architecture, the proposal defines reviewable follow-up boundaries and explicitly lists unresolved owners/decisions, with no implied implementation or release-policy approval.

Implementation acceptance scenarios for each follow-up package are authored and accepted separately. At minimum, the egress package must decide how firewall bootstrap inputs are trusted and test their fetch path, forbidden DNS transport/tunneling, IPv4/IPv6, redirects/CDNs, and local builder traffic, and distinguish verification failure from artifact acceptance. Offline evidence must use an independently authenticated approval manifest and physical network unavailability. Revocation must be checked at build and promotion boundaries, while last-known-good recovery must not reintroduce a revoked digest.

## Architecture and decisions

- Relevant source map: `docs/build-inputs.md`, `tools/airgap-bundle.sh`, `tools/unpinned-input-guard.sh`, `tools/release-promote.sh`, `docs/sbom-interchange.md`, `packer/plugins.pkr.hcl`, `packer/scripts/`, `nixos/flake.lock`, `.github/workflows/`.
- Current phase map (investigation baseline):

| Phase | Inputs / current control | Evidence boundary and gap |
|---|---|---|
| Host setup and Packer initialization | Packer binary, plugin declarations, workflow actions; plugin versions are pinned in `packer/plugins.pkr.hcl`. | Runs before the guest exists. Guest `00-egress-restrict.sh` cannot constrain host downloads. Audit action refs, plugin artifact digests, and host egress separately. |
| ISO boot and OS installer | Base ISO and installer-time package/repository traffic. Ubuntu autoinstall config sets `package_upgrade: true` and requests `util-linux-extra` plus `open-vm-tools`. | Happens before guest provisioning; current guest egress rule does not apply. The installer can resolve changing repository versions before the guest manifest exists; network boundary and package closure are not proven reproducible. |
| Guest provisioning | apt/dnf repositories and packages, downloaded binaries/scripts. `00-egress-restrict.sh` is opt-in and runs before later provisioners; default remains unrestricted. | Before its firewall rules exist, the script runs `apt-get update` and installs `dnsmasq`/`ipset` without egress restriction. The subsequent rule uses IPv4 `iptables` and explicitly permits UDP/TCP DNS to `1.1.1.1` and `8.8.8.8`; assess IPv6 and DNS transport/tunneling, redirects/CDNs, and local builder paths before claiming arbitrary egress is blocked. Real restricted builds are recorded only for Ubuntu 26.04/ext4 ARM64 on VirtualBox and VMware. |
| NixOS build | `nixos/flake.lock`, Nix/NixOS inputs and nixos-generators; build instructions include a floating `github:nix-community/nixos-generators` invocation. | Separate build path from the Ubuntu/Rocky Packer guest rule; no equivalent restricted-egress or offline-closure evidence is recorded here. |
| CI and release | GitHub Actions, setup/download actions, hosted/self-hosted runners, build and artifact-promotion workflows. | Workflow action and runner network inputs are separate from guest egress. Release rejection/promotion behavior needs its own test boundary. |

### Egress code-review findings (static analysis; runtime behavior not independently tested here)

- `00-egress-restrict.sh` installs an IPv4 `iptables` OUTPUT chain (`family inet` ipset); this script has no IPv6 filter setup. IPv6 bypass is possible if a build guest has usable IPv6, but availability was not tested.
- Before installing the firewall chain, the same script runs `apt-get update` and installs `dnsmasq`/`ipset`; that bootstrap traffic is outside the rule it is setting up. Repository trust/versioning and whether bootstrap dependencies can come from a pre-approved offline source must be decided and tested separately.
- It explicitly permits direct UDP/TCP DNS to `1.1.1.1` and `8.8.8.8` without limiting query names. That permits arbitrary DNS queries and leaves DNS tunneling possible; no tunnel was attempted.
- Allowed names populate an IP set and the firewall accepts any protocol/port to those destination IPs. This is destination-IP filtering, not HTTP host/SNI filtering. A redirect to an IP outside the set should be dropped; a different service or virtual host sharing an allowed CDN IP may remain reachable. Redirect and shared-CDN cases were not tested.
- The guest OUTPUT chain does not restrict host-side Packer/plugin/ISO downloads or runner traffic. Ubuntu installer configuration uses Packer's local HTTP server before provisioners run; provisioner SSH/SFTP replies remain allowed by ESTABLISHED/RELATED. These are source-level conclusions, not packet captures.
- Both Rocky templates pass the opt-in variable and list this script first, but the script invokes `apt-get update/install` unconditionally when enabled. Rocky opt-in therefore appears likely to fail before applying the restriction; no Rocky restricted build was run.
- CI's live mechanism test checks an allowed `raw.githubusercontent.com` request, a blocked `example.com` request, and restoration. It does not exercise IPv6, direct DNS, redirects/CDN sharing, host traffic, or Rocky. The only recorded real Packer restricted-egress builds are Ubuntu 26.04/ext4 ARM64 on VirtualBox and VMware.
- `tools/unpinned-input-guard.sh` scans shell files under `packer/scripts` and `tools`, plus top-level `packer/*.pkr.hcl`; it does not scan `nixos/` or `.github/workflows/`. The floating nixos-generators GitHub reference and workflow action refs therefore need explicit treatment in the immutable-input package; whether to broaden this guard or use ecosystem-native lock/pin checks is undecided.
- Existing negative checksum substitution exercises dool only. No equivalent negative substitution is recorded for yq, base ISO checksums, or Packer plugin artifacts; these are follow-up test cases, not current controls.

### Current SBOM, offline bundle, and release rollback boundaries

| Mechanism | What exists | Gap relevant to #30 |
|---|---|---|
| Guest inventory / provenance | `generate-sbom.sh` writes installed dpkg/rpm inventory and, when Trivy exists, SPDX/CycloneDX files. `manifest.json` records source, commit SHA, build ID, workflow run, target, and generator. | Trivy is not pinned/guaranteed; output is not CI-gated or signed. It does not enumerate the full host/tool/repository input closure. The final box digest is generated after guest manifest creation and linked separately by build ID. |
| Release evidence / promotion | `release-promote.sh` validates evidence files and requires a release `sbom.json` before promotion. Artifact digest evidence and SBOM use a build ID join. | `docs/sbom-interchange.md` records that no repo script currently produces/copies the guest SBOM into `release-evidence/$VERSION/sbom.json`; this step is manual. The gate does not establish authenticated input revocation. |
| Air-gap bundle | `airgap-bundle.sh` prepares the pinned ISO, signing key, and a small named apt package set; `verify` checks the bundle's generated SHA256SUMS without network. | It is not the full dependency closure, its checksum list is generated from the contents rather than an independent approval manifest, and no Packer build is proven to consume it with the builder network physically disabled. For example, the bundle package list omits packages used by provisioning such as `sysstat`, `tcpdump`, `jq`, `cloud-guest-utils`, and the egress bootstrap's `dnsmasq`; transitive closure has not been computed. |
| Artifact rollback | `release-promote.sh rollback` selects a previously verified staging/production artifact version. | This protects a box artifact; it does not quarantine/revoke a build input or prove that a restored build excludes a compromised digest. |

- ADR threshold result: `required` — the choice changes build/release trust boundaries, network behavior, package availability and recovery.
- No implementation choice is accepted in this draft. The maintainer/reviewer must decide:
  - `Q1` — Which maintainer owns each follow-up package and what boundary keeps implementation independently reviewable?
  - `Q2` — Which phases enter the initial egress package (start with exercised guest provisioning); should host and installer enforcement be separate packages?
  - `Q3` — Which supported target matrix and real-build evidence are required before a release policy becomes mandatory?
  - `Q4` — Which signed repository snapshot mechanism preserves full transitive resolution and historical availability while allowing security updates?
  - `Q5` — How do Nix closure, GitHub Actions, Packer, and host tooling enter the immutable input inventory?
  - `Q6` — Which provenance format, signing identity, retention, and consumers are required?
  - `Q7` — Is cooling practical, and who owns its clock, review, and exception? How is authenticated revocation checked at build/promotion, with cache cleanup best effort?

## Change impact

| Area | Impact / evidence needed |
|---|---|
| Source / command | Inventory build entrypoints and input guards; no runtime changes in this package |
| Dependencies / lockfiles | Document apt, Nix, Packer, and downloaded-tool gaps for follow-up design |
| Runtime / toolchain | Map current phase behavior and identify needed builder evidence |
| CI / CD | Record current guard/test coverage; no new gate in this package |
| Release / packaging | Document current artifact acceptance/promotion boundary |
| Generated output | Map guest SBOM vs missing build-input provenance |
| Security / supply chain | Propose separately reviewable trust-boundary packages |
| Offline / air-gap | Document current bundle verification and missing Packer consumption evidence |
| Documentation / operations | Correct evidence and record package decisions; no recovery policy adoption yet |
| Portfolio / downstream repositories | Identify consumers for follow-up provenance design |

## Verification plan

| Acceptance ID | Verification method | Environment | Expected evidence |
|---|---|---|---|
| `AC-001` | Compare docs with issue evidence; audit templates, scripts, workflows, Nix, and phase boundaries | Repository audit + referenced real-run logs | Accurate target evidence and phase/input/enforcement matrix |
| `AC-002` | Review package split and decision checklist against #30 | Maintainer review | Named boundaries, owners/decisions, no implied implementation approval |

Each follow-up package must define its applicable verification matrix and distinguish real Packer builds from fixture/CI mechanism tests. Do not infer matrix coverage from `packer validate`.

## Rollout, rollback and recovery

- Follow-up packages must be separately accepted and reviewable: package reproducibility; egress enforcement; offline bundle plus provenance/revocation. Cooling remains optional until operational ownership is established.
- Do not flip egress defaults or change package sources until the accepted matrix has real build evidence. Keep changes that alter release input resolution separately revertible.
- A follow-up revocation package must check an authenticated deny decision at build and promotion boundaries; deleting cached/bundled copies is best-effort cleanup, not the revocation guarantee.
- Recovery must not bypass accepted signature/checksum checks or reintroduce a revoked input. Any exception policy requires an owner, reason, scope, expiry, and audit record.

## Evidence and durable synchronization

- Evidence location/format: this investigation PR links per-target evidence and a phase/input/enforcement map; never label a fixture as a release build.
- Durable implementation regression controls will be defined by accepted follow-up packages; this investigation package adds no runtime policy.
- Documentation to update: `docs/build-inputs.md`, `docs/sbom-interchange.md`, build and release usage docs, input quarantine/recovery guide.
- ADR/evidence/portfolio records to update: supply-chain input trust ADR; `docs/VERIFICATION_STATUS.md`; #30 and downstream release/evidence consumers.

## Review record

- Accepted scope/requirements: pending maintainer acceptance of this draft.
- Material changes after acceptance and re-review: none.
- Open questions: `Q1`–`Q7` above; implementation must not start until the selected choices and scope are accepted.
