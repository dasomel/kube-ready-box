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
# image state. .github/workflows is skipped in full -- not because its
# content is exempt, but because a workflow's `run:` steps execute on the
# ephemeral GitHub Actions *runner*, never on a kube-ready-box image; the
# `iptables -D/-F/-X` in validate.yml's negative-test job (~line 217-219),
# for example, tears down a *test* egress chain on that runner, which is CI
# test infra, not the host-image mutation this guard exists to catch. Also
# documented in docs/host-security-baseline.md.
SKIP_PREFIXES = (
    "docs/", "research/", "templates/", "tools/tests/",
    ".github/", ".claude/", ".agent/", ".agents/",
)
SKIP_EXACT = {"tools/host-mutation-guard.sh"}
# The file types that can actually carry a host mutation in this repo: shell
# provisioners/validators, Nix modules, Kickstart, Packer/Vagrant templates,
# cloud-init/system config, the Rust verifier. Matches #44 CHANGE.md's Scope
# list, extended to the config formats packer/nixos/rocky content can use
# even though none currently do (.yaml/.yml/.conf/.tpl).
SCAN_EXTENSIONS = (".sh", ".nix", ".cfg", ".hcl", ".rs", ".yaml", ".yml", ".conf", ".tpl")


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


# --- normalization: classify a line the same way regardless of how it's
# actually invoked ----------------------------------------------------------
# `sudo setenforce 0`, `env FOO=bar iptables -F`, `command iptables -F`, and
# `exec iptables -F` must be caught exactly like the bare form (detection is
# already prefix-agnostic since every detector above searches the whole line
# rather than anchoring to its start -- but the *allowlist* patterns below do
# anchor, e.g. `^setenforce 1\b`, so a legitimate allowlisted line prefixed
# with `sudo` must not be misclassified as a brand-new, unapproved form).
# `command -v`/`command -p` are the builtin's own query flags, not a
# passthrough to a real command, so they are deliberately left alone.
LEADING_PREFIX_RE = re.compile(
    r"^\s*(?:"
    r"sudo(?:\s+-[A-Za-z]+)*\s+"
    r"|env(?:\s+[A-Za-z_][A-Za-z0-9_]*=\S+)+\s+"
    r"|command\s+(?!-)"
    r"|exec\s+"
    r")"
)
# `/usr/sbin/iptables -F` must classify identically to `iptables -F`.
ABS_TOOL_PATH_RE = re.compile(
    r"(?<![\w/-])(?:/usr/local/s?bin/|/usr/s?bin/|/s?bin/)"
    r"(iptables|nft|ufw|firewall-cmd|setenforce|aa-disable|systemctl|getenforce|aa-status)\b"
)


def normalize(line):
    normalized = line
    previous = None
    while previous != normalized:
        previous = normalized
        normalized = LEADING_PREFIX_RE.sub("", normalized, count=1)
    return ABS_TOOL_PATH_RE.sub(lambda m: m.group(1), normalized)


def logical_lines(raw_lines):
    # Join backslash-line-continued physical lines into one logical line
    # before classification, reporting the *first* physical line's number --
    # `iptables \` + `  -F KUBE_READY_EGRESS` must be classified (and denied,
    # if unallowlisted) as a single `iptables -F ...` invocation, not missed
    # because neither physical line contains it whole.
    i, n = 0, len(raw_lines)
    out = []
    while i < n:
        start = i + 1
        buf = raw_lines[i].rstrip("\n")
        while buf.rstrip().endswith("\\") and i + 1 < n:
            i += 1
            buf = buf.rstrip()[:-1] + " " + raw_lines[i].rstrip("\n")
        out.append((start, buf))
        i += 1
    return out


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
        re.compile(r"^firewall-cmd\b.*--add-service=ssh\b"),
        re.compile(r"^firewall-cmd\b.*--reload\b"),
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
    for lineno, raw in logical_lines(lines):
        if raw.lstrip().startswith("#"):
            continue
        normalized = normalize(raw)
        forms = detect_forms(normalized)
        if not forms:
            continue
        if is_allowed(rel, normalized):
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
