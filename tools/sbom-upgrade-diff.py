#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
"""Compare package inventories emitted by kube-ready-box."""

import argparse
import json
import sys


class InventoryError(Exception):
    pass


def add_package(rows, name, version, arch="", license_value=None):
    if not name:
        raise InventoryError("package name is empty")
    key = (name, arch)
    record = rows.setdefault(key, {"versions": set()})
    record["versions"].add(version)
    if license_value is not None:
        record.setdefault("licenses", set()).add(license_value)


def read_inventory(path):
    try:
        with open(path, encoding="utf-8") as stream:
            text = stream.read()
    except (OSError, UnicodeError) as exc:
        raise InventoryError(f"cannot read {path}: {exc}") from exc
    if not text.strip():
        raise InventoryError(f"empty inventory: {path}")
    if text.lstrip().startswith(("{", "[")):
        try:
            return parse_sbom(path, json.loads(text))
        except json.JSONDecodeError as exc:
            raise InventoryError(f"invalid JSON inventory {path}: {exc}") from exc

    rows = {}
    kind = None
    skipped = 0
    for line_number, line in enumerate(text.splitlines(), 1):
        if not line.strip():
            continue
        fields = line.split("\t")
        if len(fields) not in (3, 4):
            raise InventoryError(f"unsupported TSV row in {path}:{line_number}")
        row_kind = "components-tsv" if len(fields) == 3 else "packages-tsv"
        if kind is not None and kind != row_kind:
            raise InventoryError(f"mixed TSV formats in {path}:{line_number}")
        kind = row_kind
        name, version, arch = fields[:3]
        # Column meanings are from generate-sbom.sh:39-43; 4th field is
        # dpkg status or rpm installtime, never a license.
        if len(fields) == 4 and fields[3].startswith("deinstall "):
            skipped += 1
            continue
        add_package(rows, name, version, arch)
    if not rows:
        raise InventoryError(f"inventory contains zero packages: {path}")
    return kind, rows, skipped


def parse_sbom(path, data):
    if not isinstance(data, dict):
        raise InventoryError(f"invalid JSON inventory shape: {path}")
    rows = {}
    if isinstance(data.get("spdxVersion"), str) and data["spdxVersion"].startswith("SPDX-"):
        packages = data.get("packages")
        if not isinstance(packages, list):
            raise InventoryError(f"invalid SPDX packages shape: {path}")
        for package in packages:
            if not isinstance(package, dict) or not isinstance(package.get("name"), str):
                raise InventoryError(f"invalid SPDX package record: {path}")
            version = package.get("versionInfo", "")
            if not isinstance(version, str):
                raise InventoryError(f"invalid SPDX version: {path}")
            license_value = package.get("licenseConcluded") or package.get("licenseDeclared")
            if license_value == "NOASSERTION":
                license_value = None
            if license_value is not None and not isinstance(license_value, str):
                raise InventoryError(f"invalid SPDX license: {path}")
            add_package(rows, package["name"], version, package.get("primaryPackagePurpose", ""), license_value)
        kind = "spdx"
    elif data.get("bomFormat") == "CycloneDX":
        components = data.get("components")
        if not isinstance(components, list):
            raise InventoryError(f"invalid CycloneDX components shape: {path}")
        for component in components:
            if not isinstance(component, dict) or not isinstance(component.get("name"), str):
                raise InventoryError(f"invalid CycloneDX component record: {path}")
            version = component.get("version", "")
            arch = component.get("architecture", "")
            if not isinstance(version, str) or not isinstance(arch, str):
                raise InventoryError(f"invalid CycloneDX component fields: {path}")
            licenses = component.get("licenses", [])
            if not isinstance(licenses, list):
                raise InventoryError(f"invalid CycloneDX licenses shape: {path}")
            license_values = []
            for item in licenses:
                if not isinstance(item, dict):
                    raise InventoryError(f"invalid CycloneDX license record: {path}")
                license_obj = item.get("license", {})
                if not isinstance(license_obj, dict):
                    raise InventoryError(f"invalid CycloneDX license object: {path}")
                value = license_obj.get("id") or license_obj.get("name")
                if value is not None and not isinstance(value, str):
                    raise InventoryError(f"invalid CycloneDX license value: {path}")
                if value:
                    license_values.append(value)
            add_package(rows, component["name"], version, arch, " AND ".join(sorted(set(license_values))) if license_values else None)
        kind = "cyclonedx"
    else:
        raise InventoryError(f"unsupported JSON inventory format: {path}")
    if not rows:
        raise InventoryError(f"inventory contains zero packages: {path}")
    return kind, rows, 0


def version_value(values):
    ordered = sorted(values)
    return ordered[0] if len(ordered) == 1 else ordered


def compare(old, new, old_skipped=0, new_skipped=0):
    old_keys, new_keys = set(old), set(new)
    added = [{"name": n, "arch": a, "version": version_value(new[(n, a)]["versions"])} for n, a in sorted(new_keys - old_keys)]
    removed = [{"name": n, "arch": a, "version": version_value(old[(n, a)]["versions"])} for n, a in sorted(old_keys - new_keys)]
    changed, license_changed = [], []
    for key in sorted(old_keys & new_keys):
        before, after = old[key], new[key]
        if before["versions"] != after["versions"]:
            changed.append({"name": key[0], "arch": key[1], "from": version_value(before["versions"]), "to": version_value(after["versions"])})
        if before.get("licenses") and after.get("licenses") and before["licenses"] != after["licenses"]:
            license_changed.append({"name": key[0], "arch": key[1], "from": version_value(before["licenses"]), "to": version_value(after["licenses"])})
    return {"added": added, "removed": removed, "changed": changed, "license_changed": license_changed,
            "counts": {"total": len(old_keys) + len(new_keys), "skipped_not_installed": old_skipped + new_skipped,
                       "added": len(added), "removed": len(removed), "changed": len(changed), "license_changed": len(license_changed)}}


def render_markdown(result):
    lines = ["| Change | Package | From | To |", "|---|---|---|---|"]
    for item in result["added"]:
        lines.append(f"| Added | {item['name']} ({item['arch']}) |  | {item['version']} |")
    for item in result["removed"]:
        lines.append(f"| Removed | {item['name']} ({item['arch']}) | {item['version']} |  |")
    for item in result["changed"]:
        lines.append(f"| Version | {item['name']} ({item['arch']}) | {item['from']} | {item['to']} |")
    for item in result["license_changed"]:
        lines.append(f"| License | {item['name']} ({item['arch']}) | {item['from']} | {item['to']} |")
    if len(lines) == 2:
        lines.append("| No changes |  |  |  |")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--markdown", action="store_true", help="print a Markdown change table")
    parser.add_argument("old", help="older release inventory")
    parser.add_argument("new", help="newer release inventory")
    args = parser.parse_args()
    try:
        old_kind, old_rows, old_skipped = read_inventory(args.old)
        new_kind, new_rows, new_skipped = read_inventory(args.new)
        if old_kind != new_kind:
            raise InventoryError(f"inventory formats differ: {old_kind} vs {new_kind}")
        result = compare(old_rows, new_rows, old_skipped, new_skipped)
        print(render_markdown(result) if args.markdown else json.dumps(result, sort_keys=True, indent=2))
        return 0
    except Exception as exc:
        message = str(exc) or exc.__class__.__name__
        print(f"sbom-upgrade-diff: {message.splitlines()[0]}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
