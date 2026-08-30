#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail

install -d -m 0755 /usr/local/sbin /etc/systemd/system /etc/kube-ready
cat > /usr/local/sbin/kube-ready-first-boot <<'SCRIPT'
#!/bin/bash
set -euo pipefail

if [ ! -s /etc/machine-id ]; then
  systemd-machine-id-setup
fi
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id 2>/dev/null || true

ssh-keygen -A

if [ -f /etc/kube-ready/hardened-ssh ]; then
  rm -f /home/vagrant/.ssh/authorized_keys
  install -d -m 0700 /home/vagrant/.ssh
  chown -R vagrant:vagrant /home/vagrant/.ssh
fi

# Secure Boot and TPM/vTPM are capability evidence, not requirements: report
# supported/partial/unavailable rather than assuming a provider exposes them
# (docs/identity-security.md).
secure_boot_status=unavailable
secure_boot_detail="not booted via UEFI (BIOS/legacy boot)"
if [ -d /sys/firmware/efi/efivars ]; then
  sb_var=/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c
  if [ -r "$sb_var" ]; then
    # First 4 bytes are the EFI variable attributes; byte 5 is the value.
    sb_byte=$(od -An -tu1 -j4 -N1 "$sb_var" 2>/dev/null | tr -d ' ')
    if [ "$sb_byte" = "1" ]; then
      secure_boot_status=supported
      secure_boot_detail="UEFI Secure Boot enabled"
    elif [ "$sb_byte" = "0" ]; then
      secure_boot_status=partial
      secure_boot_detail="UEFI present, Secure Boot supported but disabled by firmware/hypervisor"
    else
      secure_boot_status=unavailable
      secure_boot_detail="UEFI present but SecureBoot variable unreadable"
    fi
  else
    secure_boot_status=unavailable
    secure_boot_detail="UEFI present but SecureBoot variable not exposed by firmware/hypervisor"
  fi
fi

tpm_status=unavailable
tpm_detail="no TPM/vTPM device exposed by hypervisor"
tpm_dev=""
for cand in /dev/tpmrm0 /dev/tpm0; do
  if [ -e "$cand" ]; then tpm_dev="$cand"; break; fi
done
if [ -n "$tpm_dev" ]; then
  ver=""
  if [ -r /sys/class/tpm/tpm0/tpm_version_major ]; then
    ver=$(tr -d '\n' </sys/class/tpm/tpm0/tpm_version_major 2>/dev/null || true)
  fi
  if [ -n "$ver" ]; then
    tpm_status=supported
    tpm_detail="TPM/vTPM device present ($tpm_dev, version $ver)"
  else
    tpm_status=partial
    tpm_detail="TPM/vTPM device node present ($tpm_dev) but sysfs did not report a version; driver may not be fully bound"
  fi
fi

install -d -m 0755 /etc/vagrant-box
SECURE_BOOT_STATUS="$secure_boot_status" SECURE_BOOT_DETAIL="$secure_boot_detail" \
TPM_STATUS="$tpm_status" TPM_DETAIL="$tpm_detail" \
python3 - <<'PY'
import json
import os
from pathlib import Path
Path('/etc/vagrant-box/identity-attestation.json').write_text(json.dumps({
  'schema':'kube-ready-identity/v1',
  'machine_id':Path('/etc/machine-id').read_text().strip(),
  'ssh_host_keys_generated':True,
  'hardened_ssh':Path('/etc/kube-ready/hardened-ssh').exists(),
  'secure_boot':{'status':os.environ['SECURE_BOOT_STATUS'],'detail':os.environ['SECURE_BOOT_DETAIL']},
  'tpm':{'status':os.environ['TPM_STATUS'],'detail':os.environ['TPM_DETAIL']}
}, sort_keys=True, separators=(',',':'))+'\n')
PY

systemctl disable kube-ready-first-boot.service >/dev/null 2>&1 || true
rm -f /etc/systemd/system/kube-ready-first-boot.service
systemctl daemon-reload
SCRIPT
chmod 0755 /usr/local/sbin/kube-ready-first-boot

cat > /etc/systemd/system/kube-ready-first-boot.service <<'UNIT'
[Unit]
Description=kube-ready-box first boot identity initialization
ConditionPathExists=/usr/local/sbin/kube-ready-first-boot
After=local-fs.target
Before=ssh.service sshd.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/kube-ready-first-boot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT

systemctl enable kube-ready-first-boot.service
