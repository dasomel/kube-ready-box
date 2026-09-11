# Research Evidence

Kube Ready Box follows the OpenForge Research Evidence Collection Standard:
https://github.com/dasomel/openforge/blob/main/docs/research-evidence.md

Collect sanitized machine-readable evidence during normal development when practical. Useful project evidence includes build/validation duration and result by provider/architecture, provisioning/install duration, retry/recovery counts, artifact/version metadata, failures by stage, and agent-assisted attempts, elapsed time, human interventions, review corrections, CI retries, and final verification.

Preserve failed builds and partial provisioning runs as well as successes. Use normalized environment labels rather than machine identity.

## Public-data rule

Only sanitized records may be committed publicly. Never publish credentials/tokens, Vagrant Cloud secrets, private URLs/IPs/hostnames, user-specific paths, personal/customer/employer data, confidential prompts/source, raw environment dumps, or security-sensitive host/network details. Raw Packer/VM logs and CI artifacts are sensitive-by-default.

Before public storage: validate against the OpenForge schema, run secret/pattern checks, review free-form fields, and publish normalized or aggregate measurements when safe redaction cannot be proven.
