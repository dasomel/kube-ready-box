# AGENTS.md - Kube Ready Box

Kubernetes-ready Ubuntu 24.04 / 26.04 (plus Rocky ARM64, NixOS) Vagrant box build via Packer, multi-arch, VirtualBox and VMware.
Change workflow and agent standards: https://github.com/dasomel/openforge/blob/main/docs/change-management.md and https://github.com/dasomel/openforge/blob/main/docs/agent-engineering.md.

## Load on demand

- Packer templates, provisioning scripts, build inputs, image-build validation: `.agents/skills/kube-ready-box-build-validation/SKILL.md`.
- Technical guide: `.agent/AGENT.md` (800+ lines, read the relevant section only); security policy `.agent/SECURITY.md`.
- Before touching a build path: `docs/mistakes-log.md` (single source of historical failures, add new ones there via `/add-mistake`, never copy them here). Lane routing: `docs/agent-playbook.md`.

## High-risk invariants

- Templates of one OS family share one provisioner sequence: Ubuntu has four (`packer/{virtualbox,vmware}-{amd64,arm64}.pkr.hcl`), Rocky has two (`packer/rocky-{virtualbox,vmware}-arm64.pkr.hcl`). Changing one means updating every template in the family.
- `packer/scripts/` run in the order each template lists them (not alphabetically). Never reorder, skip or add one without wiring it into every template of the family.
- `packer validate` reads each template alone and cannot see that drift; `tools/template-consistency-check.sh` can (run by `./packer/build.sh validate`, `make lint`, CI).
- Do not tweak a working 0.1.0-era build setting (`boot_wait`, `boot_command`, `http_directory`, ...) without cause; compare with `git show 327f8dc:packer/<file>` first (mistakes-log #6).
- Evidence status: `UNKNOWN` (check could not establish the property) is never healthy -- never map it to `PASS`/green or swallow it in an aggregator; it does not fail a run by itself, so failing on it is an explicit opt-in (`STRICT_READINESS=1`, verifier `--strict-*`). Contract: `docs/evidence-contracts.md`.
- Never hardcode SSH keys/passwords (use vars), edit `.box` artifacts or key files (`*.pem`, `*.key`), or expose Vagrant Cloud credentials.

## Verification

```bash
./packer/build.sh validate   # Packer validate for all templates + consistency check
make lint                    # shellcheck (warning+), bash -n, consistency and host-mutation guards, actionlint if installed
make test                    # Rust verifier + contract/tool tests
```

`bash -n` alone is not evidence. Scripts that depend on Linux runtime (`/proc`, `/sys`, services, filesystem semantics) cannot be verified on macOS (BSD tools differ; mistakes-log #23): run them in a Linux container or VM, e.g. `docker run --rm --entrypoint bash -v "$PWD:/w" -w /w <image-with-python3> -c 'bash /w/<script>'`.

Local/disposable edit-build-test work is fine; release, upload, Vagrant Cloud and other shared or destructive actions need explicit authorization.
