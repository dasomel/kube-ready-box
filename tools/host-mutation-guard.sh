#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
#
# #44 C-15/REQ-007: kube-ready-box is an observe-and-preserve evidence
# provider -- it must never blindly mutate a host's firewall or LSM
# (AppArmor/SELinux) state. This statically scans the tracked source tree for
# the mutation forms `iptables|nft|ufw|firewall-cmd|setenforce|aa-disable|
# systemctl (stop|disable) apparmor|apparmor=0|selinux=0`, plus the
# declarative NixOS toggles that disable enforcement
# (`security.apparmor.enable`/`networking.firewall.enable` set to `false`).
#
# Matching is per line/form, not per file: an allowlisted file (below) still
# fails on any mutating line that isn't one of its specifically-approved
# forms -- adding e.g. `setenforce 0` to rocky-tuning.sh fails exactly like
# adding it anywhere else. Read-only invocations of these same tools (`nft
# list ruleset`, `ufw status`, `firewall-cmd --state`, `getenforce`,
# `aa-status`, `iptables -S/-L/-C`, `command -v ufw`, ...) are never flagged,
# in any file -- kube-ready-box's own validators use them constantly to
# report state truthfully.
#
# This is regex-based line classification, not a shell parser: it cannot see
# through indirection (a mutation built from a variable, `eval`, or a
# downloaded script). It is a lint-time tripwire for the direct, literal
# forms above, not a sandbox.
set -euo pipefail

ROOT="${GUARD_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

python3 - "$ROOT" <<'PY'
import os
import re
import subprocess
import sys

root = sys.argv[1]

# --- what gets scanned -----------------------------------------------------
# Docs/plans, this guard's own tests, and CI job definitions are not shipped
# image state -- .github/workflows negative-test jobs, in particular, run
# real `iptables -D/-F/-X` to tear down a *test* egress chain on the CI
# runner itself (validate.yml:217-219), which is CI test infra, not a host
# mutation this guard exists to catch.
SKIP_PREFIXES = (
    "docs/", "research/", "templates/", "tools/tests/",
    ".github/", ".claude/", ".agent/", ".agents/",
)
SKIP_EXACT = {"tools/host-mutation-guard.sh"}
# Restricted to the file types that can actually carry a host mutation in
# this repo (shell provisioners/validators, Nix modules, Kickstart, Packer
# templates, the Rust verifier) -- matches #44 CHANGE.md's Scope list.
SCAN_EXTENSIONS = (".sh", ".nix", ".cfg", ".hcl", ".rs")


def is_scanned(path):
    if path in SKIP_EXACT or path.endswith(".md"):
        return False
    if any(path.startswith(p) for p in SKIP_PREFIXES):
        return False
    return path.endswith(SCAN_EXTENSIONS)


def tracked_files(root):
    # Prefer `git ls-files` (the real, committed tree). Falls back to a plain
    # walk so tests can point GUARD_ROOT at a throwaway fixture directory
    # that was never `git init`-ed.
    try:
        out = subprocess.run(
            ["git", "-C", root, "ls-files", "-z"],
            capture_output=True, check=True,
        )
        files = [p for p in out.stdout.decode("utf-8", "surrogateescape").split("\0") if p]
        if files:
            return files
    except (OSError, subprocess.CalledProcessError):
        pass
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d != ".git"]
        for name in filenames:
            rel = os.path.relpath(os.path.join(dirpath, name), root)
            found.append(rel)
    return found


# --- mutation-form detectors -------------------------------------------------
# Each detector fires only on a *mutating* invocation, so a read-only form
# (list/status/--state/check/get*) of the same tool never needs an allowlist
# entry anywhere.
IPTABLES_WORD = re.compile(r"(?<![\w-])iptables(?![\w-])")
IPTABLES_MUT_FLAG = re.compile(
    r"(?:^|\s)(?:-[AIDRNXFPE]|--(?:append|insert|delete-chain|delete|replace"
    r"|new-chain|flush-chain|flush|policy|rename-chain))(?:\s|$)"
)
NFT_MUT = re.compile(
    r"(?<![\w-])nft(?![\w-])\s+(?:-f\b|(?:add|insert|delete|create|destroy|flush|rename|replace)\b)"
)
UFW_MUT = re.compile(
    r"(?<![\w-])ufw(?![\w-])\s+(?:enable|disable|allow|deny|reject|limit|delete|reset|default|reload|route|insert)\b"
)
FWCMD_WORD = re.compile(r"(?<![\w-])firewall-cmd(?![\w-])")
FWCMD_MUT_FLAG = re.compile(
    r"--(?:add-[a-z0-9-]+|remove-[a-z0-9-]+|reload\b|set-[a-z0-9-]+|panic-on\b"
    r"|panic-off\b|new-zone\b|delete-zone\b|change-zone\b|complete-reload\b)"
)
SETENFORCE_MUT = re.compile(r"(?<![\w-])setenforce(?![\w-])\s+\S+")
AADISABLE_MUT = re.compile(r"(?<![\w-])aa-disable(?![\w-])")
SYSTEMCTL_APPARMOR_MUT = re.compile(
    r"(?<![\w-])systemctl(?![\w-])\s+(?:--\S+\s+)*(?:stop|disable)\s+(?:--\S+\s+)*apparmor(?:\.service)?\b"
)
APPARMOR_EQ0 = re.compile(r"\bapparmor=0\b")
SELINUX_EQ0 = re.compile(r"\bselinux=0\b")
# Declarative NixOS toggles that disable enforcement (still "the same form",
# just spelled as an option assignment instead of a CLI invocation).
NIX_APPARMOR_DISABLE = re.compile(r"security\.apparmor\.enable\s*=\s*false")
NIX_FIREWALL_DISABLE = re.compile(r"networking\.firewall\.enable\s*=\s*false")


def detect_forms(line):
    forms = []
    for m in IPTABLES_WORD.finditer(line):
        if IPTABLES_MUT_FLAG.search(line[m.end():]):
            forms.append("iptables")
            break
    if NFT_MUT.search(line):
        forms.append("nft")
    if UFW_MUT.search(line):
        forms.append("ufw")
    if FWCMD_WORD.search(line) and FWCMD_MUT_FLAG.search(line):
        forms.append("firewall-cmd")
    if SETENFORCE_MUT.search(line):
        forms.append("setenforce")
    if AADISABLE_MUT.search(line):
        forms.append("aa-disable")
    if SYSTEMCTL_APPARMOR_MUT.search(line):
        forms.append("systemctl-disable-apparmor")
    if APPARMOR_EQ0.search(line):
        forms.append("apparmor=0")
    if SELINUX_EQ0.search(line):
        forms.append("selinux=0")
    if NIX_APPARMOR_DISABLE.search(line):
        forms.append("nix-apparmor-disable")
    if NIX_FIREWALL_DISABLE.search(line):
        forms.append("nix-firewall-disable")
    return forms


# --- allowlist: file -> the specific approved forms (per line, not per file) -
# rocky-tuning.sh/ks.cfg preserve Rocky's enforcing SELinux + ssh-only
# firewalld (D8); 00-egress-restrict.sh/99-cleanup.sh create and tear down
# the build-only KUBE_READY_EGRESS chain (T-016 checks it never survives);
# nixos/configuration.nix keeps its one documented D1 firewall-disable line.
ALLOWLIST = {
    "packer/scripts/rocky-tuning.sh": [
        re.compile(r"^setenforce 1\b"),
        re.compile(r"firewall-cmd --permanent --add-service=ssh"),
        re.compile(r"^firewall-cmd --reload$"),
    ],
    "packer/scripts/00-egress-restrict.sh": [
        re.compile(r"iptables -N KUBE_READY_EGRESS"),
        re.compile(r"iptables -F KUBE_READY_EGRESS"),
        re.compile(r"iptables -I OUTPUT -j KUBE_READY_EGRESS"),
        re.compile(r"iptables -A KUBE_READY_EGRESS\b"),
    ],
    "packer/scripts/99-cleanup.sh": [
        re.compile(r"iptables -D OUTPUT -j KUBE_READY_EGRESS"),
        re.compile(r"iptables -F KUBE_READY_EGRESS"),
        re.compile(r"iptables -X KUBE_READY_EGRESS"),
    ],
    # No mutating forms are present in either kickstart today (`selinux
    # --enforcing`/`firewall --enabled --service=ssh` match neither pattern
    # above) -- listed so a future scoped change has an obvious place to add
    # an approved form instead of widening this guard.
    "packer/http/rocky-9-ext4/ks.cfg": [],
    "packer/http/rocky-9-xfs/ks.cfg": [],
    "nixos/configuration.nix": [
        re.compile(r"networking\.firewall\.enable\s*=\s*false;\s*#\s*K8s CNI manages iptables/nftables"),
    ],
}


def is_allowed(path, line):
    patterns = ALLOWLIST.get(path) or []
    return any(p.search(line) for p in patterns)


violations = []
for rel in sorted(tracked_files(root)):
    if not is_scanned(rel):
        continue
    abspath = os.path.join(root, rel)
    try:
        with open(abspath, encoding="utf-8", errors="replace") as fh:
            lines = fh.readlines()
    except OSError:
        continue
    for lineno, raw in enumerate(lines, start=1):
        if raw.lstrip().startswith("#"):
            continue
        forms = detect_forms(raw)
        if not forms:
            continue
        if is_allowed(rel, raw):
            continue
        violations.append((rel, lineno, forms, raw.strip()))

if violations:
    for rel, lineno, forms, text in violations:
        print(
            f"VIOLATION: {rel}:{lineno}: unallowlisted {'/'.join(forms)} form -- {text}",
            file=sys.stderr,
        )
    print(
        f"FAIL: {len(violations)} host firewall/LSM mutation form(s) found outside the allowlist.",
        file=sys.stderr,
    )
    sys.exit(1)

print("host-mutation-guard: no unallowlisted firewall/LSM mutation forms found")
PY
