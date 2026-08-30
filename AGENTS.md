# AGENTS.md - Kube Ready Box

> Layered contract per OpenForge Agent Engineering standard (dasomel/openforge#12): this file
> stays short and high-priority. Detailed model/tool routing → [docs/agent-playbook.md](docs/agent-playbook.md).
> Historical failure patterns → [docs/mistakes-log.md](docs/mistakes-log.md) (add new ones there, not here).

## Product boundary

Kubernetes-ready Ubuntu 24.04 / 26.04 Vagrant Box build project. Packer generates multi-arch
(AMD64/ARM64) OS images for VirtualBox and VMware.

## Source of truth

| Topic | File |
|---|---|
| Build entry point | `packer/build.sh` (`init`, `validate`, `<provider>-<arch>`, `all`, `clean`) |
| Packer templates | `packer/{virtualbox,vmware}-{amd64,arm64}.pkr.hcl` |
| Provisioning scripts | `packer/scripts/` — numbered, order-dependent (`00-`...`99-`) |
| CI/CD | `.github/workflows/build-{amd64,arm64}.yml` |
| NixOS variant | `nixos/build.sh`, `nixos/configuration.nix` |
| Vagrant Cloud upload | `upload-boxes.sh` |
| Detailed technical guide | [.agent/AGENT.md](.agent/AGENT.md) (700+ lines — load sections, not the whole file) |
| Security policy | [.agent/SECURITY.md](.agent/SECURITY.md) |
| Agent/model routing playbook | [docs/agent-playbook.md](docs/agent-playbook.md) |
| Historical mistake log | [docs/mistakes-log.md](docs/mistakes-log.md) |
| Usage guide | [docs/usage.md](docs/usage.md) |
| K8s post-install | [docs/k8s-post-install.md](docs/k8s-post-install.md) |

## High-risk invariants

- **4-template rule**: the four `pkr.hcl` templates (virtualbox/vmware × amd64/arm64) share
  structure. Changing one requires updating all four and running `packer validate`.
- Provisioning scripts run in numeric order; do not reorder, skip, or add one without wiring it
  into all four templates.
- Never tweak a working 0.1.0-era build setting (`boot_wait`, `boot_command`, `http_directory`, ...)
  without cause — check `git show 327f8dc:packer/<file>` first (see mistakes-log #6).
- Never hardcode SSH keys/passwords (use vars), modify a `.box` artifact directly, expose Vagrant
  Cloud credentials, or edit key files (`*.pem`, `*.key`).

## Smallest coherent change

Make the smallest change that solves the requested problem. Do not touch unrelated code, even
code you notice is wrong nearby — report it instead (new entry in
[docs/mistakes-log.md](docs/mistakes-log.md) via `/add-mistake`, or a follow-up issue).

## Bug-fix policy

```
reproduce -> failing test/evidence -> minimal fix -> same check passes -> regression check
```

Linux-targeted scripts cannot be verified by syntax-checking on macOS alone (no `/proc`/`/sys`) —
reproduce and verify inside a container (see mistakes-log #23):

```bash
docker run --rm --entrypoint bash -v "$PWD:/w" -w /w <image-with-python3> -c 'bash /w/<script>'
```

## Canonical verification entrypoints

```bash
./packer/build.sh validate                                    # all 4 templates
find packer/scripts nixos rocky security network storage time observability tools rust \
  -type f -name '*.sh' -print0 | xargs -0 -r shellcheck --severity=warning
bash -n <script>                                               # syntax only, not sufficient alone
```

Do not claim a fix works without running the relevant command above and, for Linux-runtime-shaped
changes, real container/VM execution evidence.

## Convergence states

Every substantive task ends in one of three states (report which one, don't just report activity):

- **A — Complete**: intended behavior verified on the relevant path.
- **B — Meaningful progress**: one verified blocker removed, next blocker isolated with evidence.
- **C — Stop**: further work needs unjustified scope growth, a fragile workaround, or an
  unsupported assumption — report the evidence and stop rather than patch around it.

## Permissions

### Allowed
- Packer 템플릿 수정 (`*.pkr.hcl`)
- 프로비저닝 스크립트 수정 (`packer/scripts/`)
- 문서 수정 (`*.md`)
- GitHub Actions 워크플로우 수정
- Agent 설정 수정 (`.claude/`, `.Codex/`)

### Not allowed
- SSH 키/비밀번호 하드코딩 (var 사용)
- Box 파일 직접 수정 (`.box`)
- Vagrant Cloud 인증정보 노출
- 키 파일 수정 (`*.pem`, `*.key`)
