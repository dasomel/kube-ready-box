#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
#
# tools/release/evidence.py 의 거부/통과 규칙을 가짜 박스와 가짜 스캔/부팅 결과로 검사한다.
# 기대값은 명세에서 가져온다(코드 출력을 베끼지 않는다): 각 박스는 PASS 스캔, arm64 는 마지막
# 시도가 boot_rc=0 인 부팅 로그, amd64 는 CI run id 가 있어야 하고, 어긋나면 아무것도 쓰지 않는다.
# 실제 스캔/부팅(Lima, VMware)은 여기서 증명하지 않는다.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
EVID="$ROOT/tools/release/evidence.py"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
sha() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

AMD=ubuntu-24.04-ext4-virtualbox-amd64-0.3.5.box
ARM=ubuntu-24.04-ext4-vmware_desktop-arm64-0.3.5.box
ROC=rocky-9-xfs-vmware_desktop-arm64-0.1.4.box
NIX=nixos-kube-ready-libvirt-arm64-0.2.3.box

summary() { # $1=ev $2=short $3=arch $4=version $5=status
  local prov=vmware_desktop; [ "$3" = arm64 ] || prov=virtualbox
  cat > "$1/scan-$2-$3.summary.json" <<EOF
{"box": "dasomel/$2[$prov/$3]", "version": "$4", "status": "$5", "fixable": {"UNKNOWN": 1}, "binaries_scanned": ["usr/local/bin/yq"]}
EOF
}
catalog() { # $1=ev $2=short $3=provider $4=arch $5=version $6=box file
  mkdir -p "$1/catalog"
  cat > "$1/catalog/$2-$4.json" <<EOF
{"name": "dasomel/$2", "versions": [{"version": "$5", "providers": [{"name": "$3", "architecture": "$4", "checksum_type": "sha256", "checksum": "$(sha "$6")"}]}]}
EOF
}

# fixture <name>: 정상 상태의 dist/evidence/extra 를 만든다.
fixture() {
  F="$WORK/$1"; D="$F/dist"; E="$D/evidence"; mkdir -p "$E"
  echo amd64-bytes > "$D/$AMD"; echo arm64-bytes > "$D/$ARM"; echo rocky-bytes > "$D/$ROC"; echo nixos-bytes > "$D/$NIX"
  summary "$E" ubuntu-24.04-ext4 amd64 0.3.5 PASS; summary "$E" ubuntu-24.04-ext4 arm64 0.3.5 PASS
  summary "$E" rocky-9-xfs arm64 0.1.4 PASS
  catalog "$E" ubuntu-24.04-ext4 virtualbox amd64 0.3.5 "$D/$AMD"
  catalog "$E" ubuntu-24.04-ext4 vmware_desktop arm64 0.3.5 "$D/$ARM"
  catalog "$E" rocky-9-xfs vmware_desktop arm64 0.1.4 "$D/$ROC"
  cat > "$E/scan-ubuntu-24.04-ext4-amd64.trivy.json" <<'EOF'
{"Results": [{"Class": "os-pkgs", "Packages": [{"Name": "linux-image-6.8.0-148-generic"}, {"Name": "linux-image-6.8.0-149-generic"}, {"Name": "linux-image-generic"}]}]}
EOF
  # ubuntu arm64: 1차 실패 후 2차 성공. rocky: 1차 성공.
  printf 'kernel=6.8.0-100-generic state=degraded\nfailed_units=1\nboot_rc=1\n' > "$E/boot-ubuntu-24.04-ext4-try1.log"
  printf 'os_id=ubuntu\nkernel=6.8.0-149-generic state=running\nfailed_units=0\nkernel_version=6.8.0-149-generic\nboot_rc=0\n' > "$E/boot-ubuntu-24.04-ext4-try2.log"
  printf 'kernel=5.14.0-611.el9_7.aarch64 state=running\nboot_rc=0\n' > "$E/boot-rocky-9-xfs-try1.log"
  cat > "$F/nixos.json" <<EOF
{"file": "$NIX", "sha256": "$(sha "$D/$NIX")", "box": "dasomel/nixos-kube-ready", "version": "0.2.3",
 "provider": "libvirt", "architecture": "arm64", "kernel": "6.18.63",
 "scan": {"status": "UNKNOWN", "fixable": null, "binaries_scanned": [], "tool": "not scannable: NixOS has no dpkg/rpm database for Trivy"},
 "boot": {"status": "PASS", "log": null, "attempts": ["vagrant-qemu boot"], "note": null}}
EOF
}

run() { # 결과: RC
  RC=0; rm -rf "$F/out"
  python3 "$EVID" --release v0.3.5 --source-commit abc1234 --trigger "test trigger" --dist "$D" \
    --ci-run ubuntu-24.04-ext4=1111 --expect-version rocky=0.1.4 --extra-image "$F/nixos.json" \
    --observed-at 2026-11-22 --out-dir "$F/out" >"$F/stdout" 2>"$F/stderr" || RC=$?
}
refused() { # $1=case name $2=stderr must contain
  [ "$RC" -ne 0 ] || fail "$1: expected refusal, got exit 0"
  [ ! -e "$F/out/BOX-SHA256SUMS" ] && [ ! -e "$F/out/v0.3.5-evidence.json" ] || fail "$1: refused run still wrote outputs"
  grep -q -- "$2" "$F/stderr" || { cat "$F/stderr" >&2; fail "$1: stderr lacks '$2'"; }
}

# 1) 통과: 산출물 내용은 명세에서 정한 값과 비교한다.
fixture ok; run
[ "$RC" -eq 0 ] || { cat "$F/stderr" >&2; fail "ok: exit $RC"; }
for f in "$AMD" "$ARM" "$ROC" "$NIX"; do
  grep -q "^$(sha "$D/$f")  $f\$" "$F/out/BOX-SHA256SUMS" || fail "ok: BOX-SHA256SUMS lacks $f"
done
[ "$(wc -l < "$F/out/BOX-SHA256SUMS" | tr -d ' ')" = 4 ] || fail "ok: BOX-SHA256SUMS should have 4 lines"
python3 - "$F/out/v0.3.5-evidence.json" "$(sha "$D/$ARM")" <<'PY' || fail "ok: evidence json content"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema_version"] == 1 and d["release"] == "v0.3.5", d
assert d["source_commit"] == "abc1234" and d["observed_at"] == "2026-11-22" and d["trigger"] == "test trigger"
im = {i["file"]: i for i in d["images"]}
assert len(im) == 4, sorted(im)
arm = im["ubuntu-24.04-ext4-vmware_desktop-arm64-0.3.5.box"]
assert arm["sha256"] == sys.argv[2] and arm["box"] == "dasomel/ubuntu-24.04-ext4"
assert arm["version"] == "0.3.5" and arm["provider"] == "vmware_desktop" and arm["architecture"] == "arm64"
assert arm["kernel"] == "6.8.0-149-generic", arm["kernel"]
assert arm["scan"]["status"] == "PASS" and arm["scan"]["fixable"] == {"UNKNOWN": 1}
assert arm["scan"]["binaries_scanned"] == ["usr/local/bin/yq"]
assert arm["boot"] == {"status": "PASS", "log": "boot-ubuntu-24.04-ext4-try2.log", "note": None,
                       "attempts": ["boot-ubuntu-24.04-ext4-try1.log:rc=1", "boot-ubuntu-24.04-ext4-try2.log:rc=0"]}, arm["boot"]
amd = im["ubuntu-24.04-ext4-virtualbox-amd64-0.3.5.box"]
assert amd["boot"]["log"] == "https://github.com/dasomel/kube-ready-box/actions/runs/1111", amd["boot"]
assert amd["boot"]["attempts"] == ["build-amd64.yml run 1111 (ext4 job): success"]
assert amd["kernel"] == "6.8.0-149-generic", amd["kernel"]   # trivy 패키지 중 가장 높은 linux-image
roc = im["rocky-9-xfs-vmware_desktop-arm64-0.1.4.box"]
assert roc["boot"]["attempts"] == ["boot-rocky-9-xfs-try1.log:rc=0"] and roc["kernel"] == "5.14.0-611.el9_7.aarch64"
nix = im["nixos-kube-ready-libvirt-arm64-0.2.3.box"]
assert nix["scan"]["status"] == "UNKNOWN" and nix["scan"]["fixable"] is None
PY
echo "ok: pass case"

# 2) 스캔 summary 없음
fixture noscan; rm "$E/scan-rocky-9-xfs-arm64.summary.json"; run; refused noscan "scan summary missing"
# 3) 스캔 FAIL
fixture failscan; summary "$E" rocky-9-xfs arm64 0.1.4 FAIL; run; refused failscan "not PASS"
# 4) 스캔 UNKNOWN 은 성공이 아니다
fixture unkscan; summary "$E" ubuntu-24.04-ext4 amd64 0.3.5 UNKNOWN; run; refused unkscan "'UNKNOWN', not PASS"
# 5) 부팅 1차 실패만 있고 재시도 없음
fixture bootfail; rm "$E/boot-ubuntu-24.04-ext4-try2.log"; run; refused bootfail "boot_rc=1"
# 6) arm64 박스에 부팅 로그 없음
fixture noboot; rm "$E/boot-rocky-9-xfs-try1.log"; run; refused noboot "no boot log"
# 7) 성공 뒤에 다시 실패한 시도가 있으면 최신이 우선 -> 거부
fixture regress; printf 'kernel=6.8.0-149-generic\nboot_rc=1\n' > "$E/boot-ubuntu-24.04-ext4-try3.log"; run; refused regress "try3.log ended with boot_rc=1"
# 8) 부팅 로그가 boot_rc 줄로 끝나지 않음(중단된 실행)
fixture trunc; printf 'kernel=6.8.0-149-generic\nfailed_units=0\n' > "$E/boot-rocky-9-xfs-try1.log"; run; refused trunc "does not end with a boot_rc"
# 9) summary 버전이 파일과 다름
fixture vermis; summary "$E" ubuntu-24.04-ext4 arm64 0.3.4 PASS; run; refused vermis "scan summary is for"
# 10) 파일 버전이 기대 버전과 다름(dist 에 남은 이전 릴리스 박스)
fixture stale; echo old > "$D/ubuntu-24.04-ext4-vmware_desktop-arm64-0.3.4.box"; run; refused stale "version mismatch"
# 11) amd64 박스에 CI run 없음
fixture noci
RC=0; python3 "$EVID" --release v0.3.5 --source-commit abc --trigger t --dist "$D" --expect-version rocky=0.1.4 \
  --extra-image "$F/nixos.json" --out-dir "$F/out" 2>"$F/stderr" >/dev/null || RC=$?
refused noci "needs --ci-run"
# 12) 스캔 뒤에 박스가 바뀜(후보 카탈로그 체크섬 불일치)
fixture changed; echo tampered >> "$D/$ARM"; run; refused changed "differs from the scanned candidate catalog"
# 13) 스캔 안 된 이미지가 PASS 를 주장
fixture extrapass; sed -i.bak 's/"status": "UNKNOWN"/"status": "PASS"/' "$F/nixos.json"; run; refused extrapass "must stay UNKNOWN"
# 14) 이름을 해석할 수 없는 박스는 조용히 빠지지 않는다
fixture strange; echo x > "$D/mystery.box"; run; refused strange "not a scannable box name"
# 15) 거부된 실행은 이전 산출물을 남기지 않는다
fixture stale_out; run; [ "$RC" -eq 0 ] || fail "stale_out: first run"
rm "$E/scan-rocky-9-xfs-arm64.summary.json"
RC=0; python3 "$EVID" --release v0.3.5 --source-commit abc --trigger t --dist "$D" --ci-run ubuntu-24.04-ext4=1111 \
  --expect-version rocky=0.1.4 --extra-image "$F/nixos.json" --out-dir "$F/out" 2>"$F/stderr" >/dev/null || RC=$?
refused stale_out "removed stale"
echo "PASS release-evidence-test"
