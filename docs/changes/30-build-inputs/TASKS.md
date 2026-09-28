# Tasks: #30 supply-chain investigation package

Linked Change Package: [`CHANGE.md`](CHANGE.md). **Draft; no implementation before maintainer acceptance.** This package reconciles evidence, maps current boundaries, and proposes follow-up Class C packages. It does not authorize runtime or release-policy changes.

## Inspect and establish evidence

- [ ] `T-001` (`REQ-001`) Reconcile `docs/build-inputs.md` against issue comments and retained real-run evidence; list remaining supported-target combinations.
- [ ] `T-002` (`REQ-002`) Inventory external inputs and enforcement points across host Packer/plugin fetch, OS installer, guest provisioning, Nix, and CI/release workflows.
- [ ] `T-003` (`REQ-002`) Record egress behavior and inspect IPv4/IPv6, DNS transport/tunneling, redirects/CDNs, and local builder traffic; distinguish current evidence from proposed tests.
- [ ] `T-004` (`REQ-006`) Map current guest SBOM, release evidence, airgap bundle, provenance consumers, artifact acceptance gate, and their gaps.

## Decide and split follow-up work

- [ ] `T-010` (`REQ-003`, `REQ-004`) Draft a package for immutable inputs and apt reproducibility; include full dependency closure, installer-phase resolution, signed metadata, historical availability, and security updates.
- [ ] `T-011` (`REQ-003`) Draft an egress package with an explicit phase and target boundary; include forbidden DNS/IPv6/redirect/local-builder cases and separate build failure from release artifact rejection.
- [ ] `T-012` (`REQ-003`, `REQ-005`, `REQ-006`, `REQ-007`) Draft an offline bundle/provenance/quarantine package; require an independently authenticated approval manifest, full closure, no-network consumption, revocation checks at build/promotion, and an authorized last-known-good recovery path that cannot reinstate a revoked digest.
- [ ] `T-013` (`REQ-007`) Keep cooling policy optional unless a named owner, clock, review, and emergency exception process are agreed.
- [ ] `T-014` Assign maintainers, dependencies, supported targets, acceptance evidence, and follow-up issue/PR boundaries.
- [ ] `T-015` Re-review the accepted investigation package after material scope/decision changes. Follow-up implementation requires its own accepted Class C package.

## Verify investigation

- [ ] `T-020` (`AC-001`) Check corrected evidence against the linked issue records; ensure historical statements are labeled as historical and current gaps are explicit.
- [ ] `T-021` (`AC-001`) Review the phase/input/enforcement map against relevant templates, scripts, workflows, and Nix configuration.
- [ ] `T-022` (`AC-002`) Confirm each implementation concern maps to a separate proposal or a named decision and owner.
- [ ] `T-023` Run markdown/diff hygiene checks and review links; no runtime tests are applicable to this documentation-only package.

## Synchronize durable truth

- [ ] `T-030` Update `docs/build-inputs.md` with observed current egress-build coverage.
- [ ] `T-031` Link the issue and any accepted follow-up packages; keep #30 open until its acceptance criteria have implementation evidence.
- [ ] `T-032` Record remaining unverified paths and package owners in the project verification/status record once decisions are made.

## Completion review

- [ ] Investigation acceptance criteria have observed evidence.
- [ ] No implementation or release policy is implied by this package.
- [ ] Follow-up package boundaries, owners, decisions, and target-specific verification are clear.
- [ ] #30 remains open until its requirements are implemented and verified.
