#!/usr/bin/env python3
"""릴리스 증거 생성기 (stdlib 전용, Python >= 3.10).

packer/dist 의 .box 와 packer/dist/evidence 의 스캔/부팅 결과로 두 파일을 만든다:
  BOX-SHA256SUMS           "<sha256>  <file>" (파일 이름순)
  v<release>-evidence.json 스키마: docs/releases/v0.3.4-evidence.json

  tools/release/evidence.py --release v0.3.5 --source-commit <sha> --trigger "<text>" \\
      --dist packer/dist --ci-run ubuntu-24.04-ext4=<run-id> ... \\
      [--expect-version rocky=0.1.4] [--extra-image nixos.json] [--out-dir DIR]

규칙(하나라도 어기면 아무것도 쓰지 않고 exit 1, 이전에 만든 산출물도 지운다):
- 모든 ubuntu/rocky 박스에 스캔 summary 가 있고 status 가 PASS 여야 한다. UNKNOWN 은 성공이 아니다.
- summary 의 box/version 이 파일 이름과 같아야 하고, 스캔 때 만든 후보 카탈로그의 sha256 이 지금
  파일의 sha256 과 같아야 한다(스캔 뒤 박스가 바뀌지 않았다는 증거).
- arm64 박스는 boot-<short>-try<N>.log 가 있고 "마지막 시도"의 마지막 줄이 boot_rc=0 이어야 한다.
  (D1: 재시도 이력은 attempts 에 남고, 성공 뒤에 다시 실패한 시도가 있으면 최신이 우선이라 거부한다.)
- amd64 박스는 --ci-run <short>=<build-amd64.yml run id> 가 있어야 한다.
- 계열별 기대 버전: ubuntu 는 릴리스 번호, 그 외는 --expect-version <family>=<ver>. 다르면 거부한다
  (D2: dist 에 이전 릴리스 .box 가 남아 있으면 조용히 건너뛰지 않고 거부한다. 치우거나 --dist 를 바꾼다).
- 스캔 대상이 아닌 이미지(NixOS)는 --extra-image <json> 으로만 넣는다. scan.status 는 UNKNOWN 이어야 하고
  boot.status 는 PASS 여야 한다.
"""
import argparse
import hashlib
import json
import os
import re
import sys
from datetime import date

NAME_RE = re.compile(
    r"^((ubuntu-[0-9]+\.[0-9]+|rocky-[0-9]+)-(ext4|xfs))-(virtualbox|vmware_desktop|libvirt)"
    r"-(amd64|arm64)-([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.]+)?)\.box$")
REL_RE = re.compile(r"^v([0-9]+\.[0-9]+\.[0-9]+)$")
BOOT_LOG_RE = re.compile(r"^boot-(.+)-try([0-9]+)\.log$")
BOOT_RC_RE = re.compile(r"^boot_rc=([0-9]+)$")
REPO_URL = "https://github.com/dasomel/kube-ready-box"


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_json(path, errors, what):
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        errors.append("%s missing: %s" % (what, path))
    except ValueError as e:
        errors.append("%s is not valid JSON: %s (%s)" % (what, path, e))
    return None


def trivy_version(repo_root):
    wf = os.path.join(repo_root, ".github", "workflows", "box-cve-scan.yml")
    try:
        with open(wf) as f:
            m = re.search(r"^  TRIVY_VERSION:\s*([0-9][0-9.]*)\s*$", f.read(), re.M)
    except OSError:
        return None
    return m.group(1) if m else None


def kernel_from_trivy(path):
    """trivy.json 의 OS 패키지에서 커널 버전을 찾는다(없으면 None)."""
    try:
        with open(path) as f:
            report = json.load(f)
    except (OSError, ValueError):
        return None
    found = []
    for res in report.get("Results") or []:
        if res.get("Class") != "os-pkgs":
            continue
        for pkg in res.get("Packages") or []:
            name = pkg.get("Name", "")
            m = re.match(r"^linux-image-([0-9][0-9.]*-[0-9]+-generic)$", name)
            if m:
                found.append(m.group(1))
    if not found:
        return None
    return max(found, key=lambda v: [int(x) for x in re.findall(r"[0-9]+", v)])


def read_boot(ev_dir, short, errors):
    """boot-<short>-try<N>.log 들을 읽어 (status, log, attempts, kernel) 을 돌려준다."""
    tries = []
    for name in os.listdir(ev_dir) if os.path.isdir(ev_dir) else []:
        m = BOOT_LOG_RE.match(name)
        if m and m.group(1) == short:
            tries.append((int(m.group(2)), name))
    tries.sort()
    if not tries:
        errors.append("%s: arm64 box has no boot log (boot-%s-try<N>.log)" % (short, short))
        return None
    attempts = []
    last_rc = None
    kernel = None
    for _, name in tries:
        with open(os.path.join(ev_dir, name), errors="replace") as f:
            lines = [ln.rstrip("\r\n") for ln in f if ln.strip()]
        m = BOOT_RC_RE.match(lines[-1]) if lines else None
        if not m:
            errors.append("%s: boot log does not end with a boot_rc=<n> line (interrupted run?)" % name)
            return None
        last_rc = int(m.group(1))
        attempts.append("%s:rc=%d" % (name, last_rc))
        for ln in lines:
            k = re.search(r"\bkernel=(\S+)", ln)
            if k and not ln.startswith("kernel_version="):
                kernel = k.group(1)
                break
    if last_rc != 0:
        errors.append("%s: latest boot attempt %s ended with boot_rc=%d" % (short, tries[-1][1], last_rc))
        return None
    return {"status": "PASS", "log": tries[-1][1], "attempts": attempts, "note": None}, kernel


def build_image(box_path, fields, args, ev_dir, ci_runs, errors):
    short, provider, arch, version = fields
    fname = os.path.basename(box_path)
    n0 = len(errors)
    sha = sha256_file(box_path)

    family = short.split("-")[0]
    want = args.expect.get(family)
    if want is None:
        errors.append("%s: no expected version for family %r (use --expect-version %s=<ver>)" % (fname, family, family))
    elif version != want:
        errors.append("%s: version mismatch: file has %s, expected %s (stale box in dist?)" % (fname, version, want))

    summary = load_json(os.path.join(ev_dir, "scan-%s-%s.summary.json" % (short, arch)), errors,
                        "%s: scan summary" % fname)
    scan = None
    if summary is not None:
        status = summary.get("status")
        if status != "PASS":
            errors.append("%s: scan status is %r, not PASS" % (fname, status))
        if summary.get("box") != "dasomel/%s" % short or summary.get("version") != version:
            errors.append("%s: scan summary is for %s %s, not dasomel/%s %s" % (
                fname, summary.get("box"), summary.get("version"), short, version))
        scan = {
            "status": status,
            "fixable": summary.get("fixable"),
            "binaries_scanned": summary.get("binaries_scanned", []),
            "tool": "trivy %s via tools/box-cve-scan.sh (BOX_FILE, candidate catalog)" % (args.trivy_version or "unknown"),
        }
    cat = load_json(os.path.join(ev_dir, "catalog", "%s-%s.json" % (short, arch)), errors,
                    "%s: candidate catalog" % fname)
    if cat is not None:
        sums = [p.get("checksum") for v in cat.get("versions", []) for p in v.get("providers", [])
                if p.get("name") == provider and p.get("architecture") == arch and v.get("version") == version]
        if sha not in sums:
            errors.append("%s: sha256 %s differs from the scanned candidate catalog (box changed after the scan?)" % (fname, sha))

    kernel = None
    boot = None
    if arch == "arm64":
        res = read_boot(ev_dir, short, errors)
        if res:
            boot, kernel = res
    else:
        run = ci_runs.get(short)
        if not run:
            errors.append("%s: amd64 box needs --ci-run %s=<build-amd64.yml run id>" % (fname, short))
        else:
            fs = short.rsplit("-", 1)[1]
            boot = {"status": "PASS", "log": "%s/actions/runs/%s" % (REPO_URL, run),
                    "attempts": ["build-amd64.yml run %s (%s job): success" % (run, fs)], "note": None}
    if kernel is None:
        kernel = kernel_from_trivy(os.path.join(ev_dir, "scan-%s-%s.trivy.json" % (short, arch)))
    if len(errors) > n0:
        return None
    return {"file": fname, "sha256": sha, "box": "dasomel/%s" % short, "version": version,
            "provider": provider, "architecture": arch, "kernel": kernel, "scan": scan, "boot": boot}


def load_extra(path, dist, errors):
    data = load_json(path, errors, "extra image")
    if data is None:
        return None
    n0 = len(errors)
    for key in ("file", "sha256", "box", "version", "provider", "architecture", "kernel", "scan", "boot"):
        if key not in data:
            errors.append("%s: extra image lacks %r" % (path, key))
    if len(errors) > n0:
        return None
    if data["scan"].get("status") != "UNKNOWN":
        errors.append("%s: extra image scan.status must stay UNKNOWN (an unscanned image cannot claim %r)" % (
            path, data["scan"].get("status")))
    if data["boot"].get("status") != "PASS":
        errors.append("%s: extra image boot.status must be PASS, got %r" % (path, data["boot"].get("status")))
    box = os.path.join(dist, data["file"])
    if os.path.isfile(box):
        actual = sha256_file(box)
        if actual != data["sha256"]:
            errors.append("%s: sha256 in JSON %s != actual %s" % (data["file"], data["sha256"], actual))
    return data if len(errors) == n0 else None


def parse_args(argv):
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", ".."))
    ap = argparse.ArgumentParser(description="Generate BOX-SHA256SUMS and v<release>-evidence.json")
    ap.add_argument("--release", required=True, help="e.g. v0.3.5")
    ap.add_argument("--source-commit", required=True)
    ap.add_argument("--trigger", required=True)
    ap.add_argument("--dist", default=os.path.join(repo, "packer", "dist"))
    ap.add_argument("--evidence-dir", help="default: <dist>/evidence")
    ap.add_argument("--out-dir", help="default: <dist>")
    ap.add_argument("--ci-run", action="append", default=[], metavar="SHORT=RUN_ID")
    ap.add_argument("--expect-version", action="append", default=[], metavar="FAMILY=VER")
    ap.add_argument("--extra-image", action="append", default=[], metavar="JSON")
    ap.add_argument("--observed-at", default=date.today().isoformat())
    a = ap.parse_args(argv)
    m = REL_RE.match(a.release)
    if not m:
        ap.error("--release must look like v1.2.3")
    a.expect = {"ubuntu": m.group(1)}
    for item in a.expect_version:
        fam, sep, ver = item.partition("=")
        if not sep or not fam or not ver:
            ap.error("--expect-version needs FAMILY=VER, got %r" % item)
        a.expect[fam] = ver
    a.ci_runs = {}
    for item in a.ci_run:
        short, sep, run = item.partition("=")
        if not sep or not short or not re.match(r"^[0-9]+$", run):
            ap.error("--ci-run needs SHORT=<numeric run id>, got %r" % item)
        a.ci_runs[short] = run
    a.evidence_dir = a.evidence_dir or os.path.join(a.dist, "evidence")
    a.out_dir = a.out_dir or a.dist
    a.trivy_version = trivy_version(repo)
    return a


def main(argv=None):
    args = parse_args(argv if argv is not None else sys.argv[1:])
    sums_path = os.path.join(args.out_dir, "BOX-SHA256SUMS")
    json_path = os.path.join(args.out_dir, "%s-evidence.json" % args.release)
    errors = []
    images = []
    extras = []
    for path in args.extra_image:
        e = load_extra(path, args.dist, errors)
        if e:
            extras.append(e)
    extra_files = {e["file"] for e in extras}

    if not os.path.isdir(args.dist):
        errors.append("dist directory not found: %s" % args.dist)
    boxes = sorted(n for n in os.listdir(args.dist) if n.endswith(".box")) if os.path.isdir(args.dist) else []
    if not boxes:
        errors.append("no .box files in %s" % args.dist)
    for name in boxes:
        if name in extra_files:
            continue
        m = NAME_RE.match(name)
        if not m:
            errors.append("%s: not a scannable box name and not listed via --extra-image" % name)
            continue
        fields = (m.group(1), m.group(4), m.group(5), m.group(6))
        img = build_image(os.path.join(args.dist, name), fields, args, args.evidence_dir, args.ci_runs, errors)
        if img:
            images.append(img)
    if args.ci_runs:
        used = {i["box"].split("/", 1)[1] for i in images if i["architecture"] == "amd64"}
        for short in sorted(set(args.ci_runs) - used):
            if not any(n.startswith(short + "-") and "-amd64-" in n for n in boxes):
                errors.append("--ci-run %s given but there is no amd64 box for it in dist" % short)

    if errors:
        for path in (sums_path, json_path):
            if os.path.exists(path):
                os.remove(path)
                print("removed stale %s" % path, file=sys.stderr)
        print("REFUSED: %d problem(s), nothing written" % len(errors), file=sys.stderr)
        for e in errors:
            print("  - " + e, file=sys.stderr)
        return 1

    lines = ["%s  %s" % (i["sha256"], i["file"]) for i in images]
    for e in extras:
        if os.path.isfile(os.path.join(args.dist, e["file"])):
            lines.append("%s  %s" % (e["sha256"], e["file"]))
        else:
            print("note: %s not in dist, left out of BOX-SHA256SUMS" % e["file"], file=sys.stderr)
    lines.sort(key=lambda ln: ln.split("  ", 1)[1])
    doc = {"schema_version": 1, "release": args.release, "source_commit": args.source_commit,
           "observed_at": args.observed_at, "trigger": args.trigger, "images": images + extras}
    os.makedirs(args.out_dir, exist_ok=True)
    with open(sums_path, "w") as f:
        f.write("\n".join(lines) + "\n")
    with open(json_path, "w") as f:
        json.dump(doc, f, indent=2)
        f.write("\n")
    print("wrote %s (%d lines) and %s (%d images)" % (sums_path, len(lines), json_path, len(doc["images"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
