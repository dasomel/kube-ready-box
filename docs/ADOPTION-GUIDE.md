# kube-ready-box Adoption Guide

> First success is a reproducible VM that proves it is ready for Kubernetes/platform work, not merely a downloaded Vagrant box.

## 1. Pick the provider/architecture deliberately

Match the documented box/provider combination to the host architecture. Keep ARM64 and AMD64 verification separate where provider behavior differs.

## 2. First verified success

1. Bring up the smallest documented Vagrant environment.
2. Verify the guest OS and architecture.
3. Verify expected filesystem layout and quota capability required by the box profile.
4. Verify container/Kubernetes prerequisites exposed by the image.
5. Reboot/recreate once to confirm the environment is reproducible rather than an accidental one-shot state.

Use release/Vagrant metadata as the source of truth for exact versions instead of copying version facts into new documents.

## 3. What this box is for

The project is a reusable infrastructure substrate for Kubernetes labs, platform bootstrap, storage/quota experiments, and repeatable development environments. Higher-level platform success belongs to the project layered on top of the box.

## 4. Documentation path

Read the README first for provider-specific commands and supported combinations. Use this guide as the acceptance contract: OS/architecture, storage readiness, required tooling, and reproducibility should all be observable before calling the box ready.

## 5. Maintenance rule

When Ubuntu, filesystem defaults, provider support, Vagrant/Packer behavior, or Kubernetes prerequisites change, update the authoritative build/release metadata first and then refresh user-facing compatibility documentation.