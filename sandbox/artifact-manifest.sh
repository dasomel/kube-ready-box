#!/usr/bin/env bash
set -euo pipefail
OUT="${1:-sandbox/artifacts.json}"
RUNSC="${RUNSC_PATH:-/usr/local/bin/runsc}"
RUNTIME_CONFIG="${RUNTIME_CONFIG:-/etc/containerd/config.toml}"

sha(){ [ -f "$1" ] && sha256sum "$1" | awk '{print $1}' || echo null; }
version(){ "$1" --version 2>/dev/null | head -1 || echo unknown; }

python3 - "$OUT" "$RUNSC" "$RUNTIME_CONFIG" <<'PY'
import json,sys,os,subprocess
out,runsc,config=sys.argv[1:]
def ver(p):
 try:return subprocess.check_output([p,'--version'],stderr=subprocess.STDOUT,text=True).splitlines()[0]
 except:return 'unknown'
def sha(p):
 try:return subprocess.check_output(['sha256sum',p],text=True).split()[0]
 except:return None
obj={'schema':'kube-ready-sandbox/v1','runtime':'gvisor','runsc':{'path':runsc,'version':ver(runsc),'sha256':sha(runsc)},'containerd_config':{'path':config,'sha256':sha(config)},'network':'offline-artifact-evidence-only'}
open(out,'w').write(json.dumps(obj,sort_keys=True,separators=(',',':'))+'\n')
print(json.dumps(obj,sort_keys=True,separators=(',',':')))
PY
