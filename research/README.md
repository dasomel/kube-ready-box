# Research Evidence

Kube Ready Box follows the OpenForge Research Evidence Collection Standard:
https://github.com/dasomel/openforge/blob/main/docs/research-evidence.md

Collect machine-readable evidence during normal development when practical. Useful evidence includes build/validation duration and result by provider/architecture, provisioning/install duration, retry/recovery counts, artifact/version metadata, failures by stage, and agent-assisted attempts/interventions/review corrections/CI retries/final verification. Preserve failed builds and partial provisioning runs.

## Legacy evidence on discovery

Evidence collection is prospective and retrospective. While implementing, fixing, verifying, releasing, or documenting the project, catalog historical build logs/results, validation reports, profiling outputs, compatibility records, CI results, release evidence, and other measurements encountered during the work. Tooling that could produce a metric is not itself a historical measurement; only classify an output as measured when the output actually exists.

Use `dasomel/openforge#89` as the portfolio-level legacy catalog source of truth. Record source/path, known date, evidence class/strength, environment scope, metrics/facts, limitations, and likely paper use. Do not fabricate missing historical measurements. Preserve failures, partial runs, and obsolete provider/version results when useful longitudinally.

## Public-data rule

This is a personal OSS/test project. Provider/architecture labels, local VM names, RFC1918 addresses, test hostnames, provisioning topology, and reproducibility-relevant machine/runtime details may remain when intentionally public test data.

Never publish credentials/tokens/private keys/Vagrant Cloud secrets or accidental personal data. Review future third-party/non-public artifacts separately. Validate structured evidence against the OpenForge schema and run secret/pattern checks before publication.