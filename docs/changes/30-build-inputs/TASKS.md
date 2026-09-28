# Tasks: #30 supply-chain investigation package

Linked Change Package: [`CHANGE.md`](CHANGE.md). **Draft; no implementation before maintainer acceptance.** This package reconciles evidence, maps current boundaries, and proposes follow-up Class C packages. It does not authorize runtime or release-policy changes.

## Inspect and establish evidence

- [x] `T-001` (`REQ-001`) Reconcile `docs/build-inputs.md` against issue comments and recorded real-run evidence; list remaining supported-target combinations.
- [x] `T-002` (`REQ-002`) Inventory external inputs and enforcement points across host Packer/plugin fetch, OS installer, guest provisioning, Nix, and CI/release workflows; inspect the current unpinned-input guard's scan scope.
- [x] `T-003` (`REQ-002`) Inspect egress code for bootstrap downloads before firewall setup, IPv4/IPv6, DNS transport/tunneling, redirects/CDNs, and local builder traffic. Record these as static-analysis findings, not runtime test results.
- [x] `T-004` (`REQ-006`) Map current guest SBOM, release evidence, airgap bundle contents vs representative provisioning packages, provenance consumers, artifact acceptance gate, and their gaps.

## Decide and split follow-up work

- [x] `T-010` (`REQ-003`, `REQ-004`) Propose the immutable-input/apt-reproducibility boundary; record full dependency closure, installer-phase resolution, signed metadata, historical availability, and security-update decisions.
- [x] `T-011` (`REQ-003`) Propose the egress boundary; include forbidden DNS/IPv6/redirect/local-builder cases and separate build failure from release artifact rejection.
- [x] `T-012` (`REQ-003`, `REQ-005`, `REQ-006`, `REQ-007`) Propose the offline bundle/provenance/quarantine boundary; require an independently authenticated approval manifest, full closure, no-network consumption, revocation checks at build/promotion, and authorized last-known-good recovery that cannot reinstate a revoked digest.
- [x] `T-013` (`REQ-007`) Keep cooling optional unless a named owner, clock, review, and emergency exception process are agreed.
- [ ] `T-014` Assign maintainers, dependencies, supported targets, acceptance evidence, and follow-up issue/PR boundaries.
- [ ] `T-015` Re-review the accepted investigation package after material scope/decision changes. Follow-up implementation requires its own accepted Class C package.

## Verify investigation

- [x] `T-020` (`AC-001`) Check corrected evidence against linked issue records; historical statements are labeled and current gaps are explicit.
- [x] `T-021` (`AC-001`) Review phase/input/enforcement and SBOM/airgap/promotion maps against relevant templates, scripts, workflows, and Nix configuration.
- [x] `T-022` (`AC-002`) Map each issue concern to a follow-up boundary or a named maintainer decision; owners remain explicitly pending.
- [x] `T-023` Run `make lint` and `git diff --check`; no runtime tests apply to this docs-only package.

## Synchronize durable truth

- [x] `T-030` Update `docs/build-inputs.md` with observed current egress-build coverage.
- [x] `T-031` Link this draft to #30 and keep #30 open until its acceptance criteria have implementation evidence.
- [ ] `T-032` Record remaining unverified paths and package owners in the project verification/status record once decisions are made.

## Completion review

- [ ] Investigation acceptance criteria have observed evidence.
- [ ] No implementation or release policy is implied by this package.
- [ ] Follow-up package boundaries, owners, decisions, and target-specific verification are clear.
- [ ] #30 remains open until its requirements are implemented and verified.
