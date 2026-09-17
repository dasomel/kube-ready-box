---
name: kube-ready-box-build-validation
description: Change and validate Kube Ready Box Packer/Vagrant image builds across VirtualBox/VMware and AMD64/ARM64 while preserving the four-template invariant, ordered provisioning, Linux-runtime evidence, and artifact/security boundaries. Use for Packer templates, provisioning scripts, build inputs, box validation, or build CI changes.
license: Apache-2.0
compatibility: Requires the Kube Ready Box checkout and relevant Packer/Vagrant/provider toolchain; real build evidence depends on the target provider/architecture environment.
metadata:
  openforge-scope: project
  openforge-owner: dasomel/kube-ready-box
  openforge-maturity: verified
  openforge-version: "1"
---

# Kube Ready Box Build Validation

## Use When

- Editing `packer/*.pkr.hcl`, `packer/scripts/`, autoinstall inputs, provider/architecture build paths, or build CI.
- Diagnosing an image build/boot/provisioning failure.
- Changing an external build input that can affect reproducibility.

## Do Not Use When

- Only uploading an already verified artifact using the existing deterministic release/upload command.
- Pure documentation changes unrelated to build behavior.

## Inputs

- Provider and architecture scope: VirtualBox/VMware × AMD64/ARM64.
- Files changed and affected provisioning phase.
- Whether Linux/container/VM execution is available for runtime-shaped scripts.

## Workflow

1. Read `AGENTS.md`, the relevant section of `.agent/AGENT.md`, and `docs/mistakes-log.md` before changing the build path.
2. Preserve the four-template invariant. If a shared structural setting changes in one `pkr.hcl`, inspect and update all four provider/architecture templates coherently.
3. Preserve numeric provisioning order and ensure any new/renamed script is wired into every affected template.
4. Do not casually change known-good boot/autoinstall/provider values. Check the documented historical baseline and the failure log when touching fragile boot settings.
5. Keep secrets, SSH credentials, Vagrant Cloud tokens, key files, and generated `.box` artifacts outside source edits.
6. Run the canonical template validation (`./packer/build.sh validate`) and the repository shellcheck gate for affected scripts.
7. Treat `bash -n` as syntax evidence only. For code depending on Linux `/proc`, `/sys`, package/service behavior, filesystem, or network semantics, execute it inside a suitable Linux container/VM or real build path.
8. When the change can alter actual boot/provision behavior, run the smallest representative provider/architecture build that proves it, then expand to the required matrix according to the issue/release scope.
9. Record new reusable failure discriminators in `docs/mistakes-log.md` instead of adding another copy to agent instructions.

## Verification

Report template/static validation separately from container/VM/provider build evidence. A successful Packer syntax validation does not prove that cloud-init, provisioning scripts, guest services, or the packaged Vagrant box work.

## Stop / Escalate When

- The change would weaken secret/key handling or directly modify generated `.box` artifacts.
- A shared-template change cannot be applied coherently across the supported matrix.
- Runtime behavior is central to the completion claim but no representative Linux/provider environment can be exercised.
- Repeated changes are masking a provider/boot incompatibility rather than isolating it.

## References

- `AGENTS.md`
- `.agent/AGENT.md`
- `.agent/SECURITY.md`
- `docs/mistakes-log.md`
- `docs/build-inputs.md`
- `packer/build.sh`
