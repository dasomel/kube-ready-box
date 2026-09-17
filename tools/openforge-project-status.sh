#!/usr/bin/env bash
# Build an OpenForge portfolio status payload from committed contract evidence.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="${CONTRACT:-/tmp/kube-ready-contracts.json}"
RELEASE_EVIDENCE="${RELEASE_EVIDENCE:-$ROOT/release-evidence}"
CI_STATUS="${CI_STATUS:-not-run}"
SECURITY_STATUS="${SECURITY_STATUS:-not-run}"
REVISION="${REVISION:-$(git -C "$ROOT" rev-parse HEAD)}"
OUTPUT="${OUTPUT:-/tmp/openforge-project-status.json}"
MILESTONE="${MILESTONE:-}"
SCHEMA="$ROOT/etc/openforge-status.schema.json"

python3 - "$CONTRACT" "$RELEASE_EVIDENCE" "$CI_STATUS" "$SECURITY_STATUS" "$REVISION" "$OUTPUT" "$MILESTONE" "$SCHEMA" "${VALIDATE_PAYLOAD:-}" "${OPENFORGE_FORCE_FALLBACK_VALIDATOR:-}" <<'PY'
import datetime
import json
import os
import sys

(
    contract_path, evidence_dir, ci, security, revision, output, milestone, schema_path,
    validate_payload, force_fallback,
) = sys.argv[1:]
with open(contract_path, encoding="utf-8") as handle:
    contract = json.load(handle)
if contract.get("schema") != "kube-ready-contracts/v1" or not isinstance(contract.get("reports"), list):
    raise SystemExit("CONTRACT must be a kube-ready-contracts/v1 document with reports[]")
allowed = {"pass", "fail", "not-run"}
if ci not in allowed or security not in allowed:
    raise SystemExit("CI_STATUS and SECURITY_STATUS must be pass, fail, or not-run")

# Only a report actually emitted by the aggregator becomes a capability claim.
mapping = {
    "readiness": "node-readiness", "network": "node-network", "storage": "node-storage",
    "time": "node-time", "security": "workload-security", "observability": "node-observability",
    "license": "license-gate", "rust_verifier": "rust-verifier", "sandbox": "sandbox",
}
# Real boot reporters predate the portfolio names; accept their recorded kinds
# without treating a generic verification matrix as evidence for a capability.
evidence_names = {
    "kubernetes-node-readiness": "node-readiness",
    "node-network-readiness": "node-network",
    "node-storage-readiness": "node-storage",
    "node-time-readiness": "node-time",
}
present = [mapping[report["name"]] for report in contract["reports"]
           if isinstance(report, dict) and report.get("name") in mapping]

def runtime_results(path):
    results = {}
    if not os.path.isdir(path):
        return results
    candidates = {}
    # D1: Sort paths so the selected report is deterministic. A capability with
    # reports in multiple release directories uses the lexicographically newest
    # directory; filenames break a tie in that directory deterministically.
    # Cost: directory names define recency; escape hatch: add dated evidence.
    for filename in sorted(
        os.path.join(base, name)
        for base, _, files in os.walk(path)
        for name in files
        if name.endswith(".json")
    ):
        try:
            with open(filename, encoding="utf-8") as handle:
                data = json.load(handle)
        except (OSError, json.JSONDecodeError):
            continue
        if not isinstance(data, dict) or data.get("status") not in ("PASS", "FAIL"):
            continue
        identifiers = [data.get(key) for key in ("capability", "report", "name", "kind")]
        identifiers.append(os.path.splitext(os.path.basename(filename))[0])
        for identifier in identifiers:
            if identifier in evidence_names:
                identifier = evidence_names[identifier]
            if identifier in mapping:
                identifier = mapping[identifier]
            if identifier in mapping.values():
                directory = os.path.relpath(os.path.dirname(filename), path)
                candidate = (directory, filename, data["status"].lower())
                if identifier not in candidates or candidate[:2] > candidates[identifier][:2]:
                    candidates[identifier] = candidate
    for capability_id, (_, _, status) in candidates.items():
        results[capability_id] = status
    return results

runtime = runtime_results(evidence_dir)
security_capabilities = {"workload-security", "sandbox", "license-gate"}
standards = {"workload-security", "sandbox"}
capabilities = {}
for capability_id in present:
    runtime_status = runtime.get(capability_id, "not-run")
    capability = {
        "status": "implemented" if runtime_status == "pass" else "verifying",
        "verification": {"unit": ci, "runtime": runtime_status,
                         "security": security if capability_id in security_capabilities else "not-applicable"},
    }
    if capability_id in standards:
        capability["standard"] = "openforge/agent-execution-security"
    capabilities[capability_id] = capability

evidence_runtime = "not-run"
if runtime:
    evidence_runtime = "fail" if any(value == "fail" for value in runtime.values()) else "pass"

payload = {
    "version": "openforge-project-status/v1", "project": "kube-ready-box",
    "repository": "dasomel/kube-ready-box",
    "revision": revision,
    "updated_at": datetime.date.today().isoformat(),
    "development": {"status": os.environ.get("DEVELOPMENT_STATUS", "active"),
                    "milestone": milestone or None, "progress_percent": None},
    "capabilities": capabilities, "relationships": [],
    "evidence": {"commit": revision, "ci": ci, "security": security,
                 "runtime": evidence_runtime},
}

with open(schema_path, encoding="utf-8") as handle:
    schema = json.load(handle)

def validate(value, rule, path="$"):
    if "const" in rule and value != rule["const"]:
        raise ValueError(f"{path} must equal {rule['const']}")
    if "enum" in rule and value not in rule["enum"]:
        raise ValueError(f"{path} must be one of {rule['enum']}")
    types = rule.get("type")
    if types:
        types = [types] if isinstance(types, str) else types
        matches = {"object": isinstance(value, dict), "array": isinstance(value, list),
                   "string": isinstance(value, str), "number": isinstance(value, (int, float)) and not isinstance(value, bool),
                   "null": value is None}
        if not any(matches.get(kind, False) for kind in types):
            raise ValueError(f"{path} has wrong type")
    if isinstance(value, dict):
        for key in rule.get("required", []):
            if key not in value:
                raise ValueError(f"{path}.{key} is required")
        for key, child_rule in rule.get("properties", {}).items():
            if key in value:
                validate(value[key], child_rule, f"{path}.{key}")
        properties = rule.get("properties", {})
        additional = rule.get("additionalProperties", True)
        for key, child_value in value.items():
            if key in properties:
                continue
            if additional is False:
                raise ValueError(f"{path}.{key} is not allowed")
            if isinstance(additional, dict):
                validate(child_value, additional, f"{path}.{key}")
    if isinstance(value, list) and "items" in rule:
        for index, item in enumerate(value):
            validate(item, rule["items"], f"{path}[{index}]")
    if "minLength" in rule and len(value) < rule["minLength"]:
        raise ValueError(f"{path} is too short")
    if "pattern" in rule and isinstance(value, str):
        import re
        if re.search(rule["pattern"], value) is None:
            raise ValueError(f"{path} does not match {rule['pattern']}")
    if "minimum" in rule and value is not None and value < rule["minimum"]:
        raise ValueError(f"{path} is below minimum")
    if "maximum" in rule and value is not None and value > rule["maximum"]:
        raise ValueError(f"{path} is above maximum")

try:
    candidate = payload
    if validate_payload:
        with open(validate_payload, encoding="utf-8") as handle:
            candidate = json.load(handle)
    if force_fallback:
        validate(candidate, schema)
    else:
        try:
            from jsonschema import Draft202012Validator
        except ImportError:
            validate(candidate, schema)
        else:
            Draft202012Validator(schema).validate(candidate)
except Exception as exc:
    raise SystemExit(f"OpenForge status schema validation failed: {exc}")

if validate_payload:
    print("OpenForge status schema validation passed")
    raise SystemExit(0)

os.makedirs(os.path.dirname(os.path.abspath(output)), exist_ok=True)
with open(output, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, sort_keys=True, separators=(",", ":"))
    handle.write("\n")
print(json.dumps(payload, sort_keys=True, separators=(",", ":")))
PY
