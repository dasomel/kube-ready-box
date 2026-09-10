# OpenForge adoption

Follow the canonical OpenForge standards:
- https://github.com/dasomel/openforge/blob/main/docs/model-agnostic-agent-instructions.md
- https://github.com/dasomel/openforge/blob/main/docs/agent-engineering.md
- https://github.com/dasomel/openforge/blob/main/docs/user-centric-validation.md

Keep Packer/provider/architecture and historical build invariants local. Load detailed playbooks and mistake-log sections only when relevant. Model/tool files are thin adapters. For image build, provisioning, install/configuration, provider, architecture, and upgrade changes, use risk-proportional validation; syntax/static checks alone do not prove Linux VM behavior. Confirmed user-visible defects become regression evidence.

Safe local/disposable work within scope may proceed autonomously. Publishing boxes/releases, shared/external mutation, destructive actions, credential/permission changes, or unrelated external mutation requires explicit authorization unless already granted.
