@AGENTS.md

> Project slash commands, hooks, and settings under `.claude/` make this adapter intentionally retained; do not remove it merely because Claude Code can fall back to `AGENTS.md`.

# Kube Ready Box Claude adapter

Repository-wide build/security boundaries live in `AGENTS.md`. Detailed technical material lives in `.agent/AGENT.md`; historical failures live in `docs/mistakes-log.md`. Do not duplicate those sources here.

## Project skill routing

For Packer templates, provisioning scripts, provider/architecture build paths, build inputs, or image-build validation, load `.agents/skills/kube-ready-box-build-validation/SKILL.md`.

## Claude-only integration

Project slash commands live in `.claude/commands/`; hooks and permissions live under `.claude/hooks/` and `.claude/settings.json`. Use those runtime-specific helpers without copying their procedures into this file.

Model/team routing guidance for Claude, Codex, and other agents lives in `docs/agent-playbook.md`.
