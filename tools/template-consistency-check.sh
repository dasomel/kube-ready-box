#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
set -euo pipefail

# #47: `packer validate` reads each template in isolation, so a provisioner
# script wired into only some templates of an OS family passes it cleanly.
# This check compares the provisioner script sequence across templates of the
# same family and fails on any difference.
#
# Order is compared, not just membership: the sequence is the documented
# execution order (00-..., ubuntu-tuning, 07-..., license-info, ...), which is
# deliberately not alphabetical.

TEMPLATE_DIR="${TEMPLATE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../packer" && pwd)}"

# Templates that declare no provisioner scripts (plugin/vmx-only definitions)
# are not part of any family's provisioning contract.
scripts_of() {
  grep -oE 'scripts/[a-zA-Z0-9._-]+\.sh' "$1" || true
}

family_of() {
  case "$(basename "$1")" in
    rocky-*) echo rocky ;;
    *) echo ubuntu ;;
  esac
}

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

families=""
found=0

for template in "$TEMPLATE_DIR"/*.pkr.hcl; do
  [ -e "$template" ] || continue
  scripts="$(scripts_of "$template")"
  [ -n "$scripts" ] || continue
  found=1

  family="$(family_of "$template")"
  case " $families " in
    *" $family "*) : ;;
    *) families="$families $family" ;;
  esac

  # Bucket templates by the exact sequence they declare. The bucket key is a
  # hash so that the sequence itself stays out of the filename.
  key="$(printf '%s\n' "$scripts" | shasum | cut -d' ' -f1)"
  mkdir -p "$WORKDIR/$family"
  printf '%s\n' "$(basename "$template")" >> "$WORKDIR/$family/$key.members"
  printf '%s\n' "$scripts" > "$WORKDIR/$family/$key.sequence"
done

if [ "$found" -eq 0 ]; then
  echo "FAIL: no templates with provisioner scripts found in $TEMPLATE_DIR" >&2
  exit 1
fi

drift=0
for family in $families; do
  # Largest bucket first: with one odd template out, the majority sequence is
  # the expected one and the minority is what actually drifted.
  buckets=()
  while IFS= read -r bucket; do
    buckets+=("$bucket")
  done < <(
    for members in "$WORKDIR/$family"/*.members; do
      printf '%s\t%s\n' "$(wc -l < "$members" | tr -d ' ')" "$members"
    done | sort -rn -k1,1 | cut -f2
  )

  if [ "${#buckets[@]}" -eq 1 ]; then
    count="$(wc -l < "${buckets[0]%.members}.sequence" | tr -d ' ')"
    echo "$family: provisioner scripts consistent across all templates ($count scripts)"
    continue
  fi

  drift=1
  expected="${buckets[0]}"
  expected_size="$(wc -l < "$expected" | tr -d ' ')"
  echo "DRIFT ($family): templates do not share one provisioner sequence" >&2

  for bucket in "${buckets[@]:1}"; do
    bucket_size="$(wc -l < "$bucket" | tr -d ' ')"
    # A tie means there is no majority to call authoritative (e.g. a
    # two-template family split 1-1); say so instead of blaming one side.
    if [ "$bucket_size" -eq "$expected_size" ]; then
      echo "  no majority sequence; these template groups disagree:" >&2
      echo "    group A: $(tr '\n' ' ' < "$expected")" >&2
      echo "    group B: $(tr '\n' ' ' < "$bucket")" >&2
    else
      echo "  drifted: $(tr '\n' ' ' < "$bucket")" >&2
      echo "  expected (matches $(tr '\n' ' ' < "$expected")):" >&2
    fi
    diff -u --label expected "${expected%.members}.sequence" \
            --label drifted "${bucket%.members}.sequence" >&2 || true
  done
done

if [ "$drift" -ne 0 ]; then
  echo "FAIL: provisioner scripts are not consistent across templates of the same OS family" >&2
  exit 1
fi
