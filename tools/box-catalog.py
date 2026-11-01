#!/usr/bin/env python3
"""Vagrant box 카탈로그(JSON) 생성/병합/검증 (GitHub Pages 용, stdlib 전용).

  box-catalog.py add --catalog site/boxes/x.json --name dasomel/x --version 1.2.0 \
      --provider vmware_desktop --arch arm64 --url https://.../x.box --box ./x.box
  box-catalog.py verify site/boxes [--box-dir DIR]

같은 version+provider+arch 에 다른 checksum 이 이미 있으면 --replace 없이는 실패한다.
"""
import argparse
import hashlib
import json
import os
import re
import sys
from urllib.parse import urlparse

HEX64 = re.compile(r"^[0-9a-f]{64}$")
SEMVER = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$")


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def semver_key(v):
    m = SEMVER.match(v)
    if not m:
        raise ValueError("not a semver: %r" % v)
    core = tuple(int(x) for x in m.groups()[:3])
    pre = m.group(4)
    if pre is None:  # 정식 릴리스가 prerelease 보다 높다
        return core, (1,)
    parts = tuple((0, int(p), "") if p.isdigit() else (1, 0, p) for p in pre.split("."))
    return core, (0,) + parts


def cmd_add(a):
    try:
        semver_key(a.version)
    except ValueError as e:
        sys.exit("error: %s" % e)
    if urlparse(a.url).scheme != "https":
        sys.exit("error: --url must be https")
    checksum = sha256_file(a.box)
    if os.path.exists(a.catalog):
        with open(a.catalog) as f:
            cat = json.load(f)
        if cat.get("name") != a.name:
            sys.exit("error: catalog name %r != --name %r" % (cat.get("name"), a.name))
    else:
        cat = {"name": a.name, "description": a.description or a.name, "versions": []}
    if a.description:
        cat["description"] = a.description
    versions = cat.setdefault("versions", [])
    ver = next((v for v in versions if v.get("version") == a.version), None)
    if ver is None:
        ver = {"version": a.version, "providers": []}
        versions.append(ver)
    provs = ver.setdefault("providers", [])
    old = next((p for p in provs if p.get("name") == a.provider
                and p.get("architecture") == a.arch), None)
    entry = {
        "name": a.provider,
        "url": a.url,
        "checksum_type": "sha256",
        "checksum": checksum,
        "architecture": a.arch,
        "default_architecture": True,
    }
    if old is not None:
        if old.get("checksum") == checksum and old.get("url") == a.url:
            print("no-op: %s %s %s/%s already present" % (a.name, a.version, a.provider, a.arch))
            return
        if not a.replace:
            sys.exit("error: %s %s %s/%s exists with checksum %s (new %s); use --replace"
                     % (a.name, a.version, a.provider, a.arch, old.get("checksum"), checksum))
        provs.remove(old)
    provs.append(entry)
    versions.sort(key=lambda v: semver_key(v["version"]), reverse=True)
    os.makedirs(os.path.dirname(os.path.abspath(a.catalog)), exist_ok=True)
    tmp = a.catalog + ".tmp"
    with open(tmp, "w") as f:
        json.dump(cat, f, indent=2)
        f.write("\n")
    os.replace(tmp, a.catalog)
    print("ok: %s %s %s/%s sha256=%s" % (a.name, a.version, a.provider, a.arch, checksum))


def verify_catalog(path, box_dir):
    errs = []
    try:
        with open(path) as f:
            cat = json.load(f)
    except (OSError, ValueError) as e:
        return ["invalid JSON: %s" % e]
    if not isinstance(cat, dict):
        return ["top level must be an object"]
    for k in ("name", "description"):
        if not isinstance(cat.get(k), str) or not cat[k]:
            errs.append("missing %s" % k)
    versions = cat.get("versions")
    if not isinstance(versions, list) or not versions:
        return errs + ["versions must be a non-empty list"]
    for v in versions:
        ver = v.get("version") if isinstance(v, dict) else None
        try:
            semver_key(ver)
        except (ValueError, TypeError):
            errs.append("bad version %r" % (ver,))
            continue
        provs = v.get("providers")
        if not isinstance(provs, list) or not provs:
            errs.append("%s: providers must be a non-empty list" % ver)
            continue
        for p in provs:
            tag = "%s/%s" % (ver, p.get("name") if isinstance(p, dict) else "?")
            if not isinstance(p, dict):
                errs.append("%s: provider must be an object" % tag)
                continue
            for k in ("name", "url", "checksum_type", "checksum", "architecture"):
                if not isinstance(p.get(k), str) or not p[k]:
                    errs.append("%s: missing %s" % (tag, k))
            if p.get("checksum_type") != "sha256":
                errs.append("%s: checksum_type must be sha256" % tag)
            if not HEX64.match(str(p.get("checksum", ""))):
                errs.append("%s: checksum is not 64 lowercase hex" % tag)
            if urlparse(str(p.get("url", ""))).scheme != "https":
                errs.append("%s: url must be https" % tag)
            if box_dir and p.get("url"):
                local = os.path.join(box_dir, os.path.basename(urlparse(p["url"]).path))
                if os.path.isfile(local) and sha256_file(local) != p.get("checksum"):
                    errs.append("%s: checksum mismatch vs %s" % (tag, local))
    return errs


def cmd_verify(a):
    files = sorted(os.path.join(a.dir, n) for n in os.listdir(a.dir) if n.endswith(".json"))
    bad = 0
    for path in files:
        errs = verify_catalog(path, a.box_dir)
        for e in errs:
            print("FAIL %s: %s" % (path, e), file=sys.stderr)
        bad += bool(errs)
        if not errs:
            print("ok %s" % path)
    if bad:
        sys.exit(1)
    print("verified %d catalog(s)" % len(files))


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("add")
    p.add_argument("--catalog", required=True)
    p.add_argument("--name", required=True)
    p.add_argument("--version", required=True)
    p.add_argument("--provider", required=True)
    p.add_argument("--arch", required=True)
    p.add_argument("--url", required=True)
    p.add_argument("--box", required=True)
    p.add_argument("--description")
    p.add_argument("--replace", action="store_true")
    p.set_defaults(fn=cmd_add)
    v = sub.add_parser("verify")
    v.add_argument("dir")
    v.add_argument("--box-dir")
    v.set_defaults(fn=cmd_verify)
    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
