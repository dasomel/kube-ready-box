//! Container runtime + CSI-prerequisite checks.

use crate::fsutil::{command_ok, exists, in_path};
use crate::json::{Check, Status};

pub fn run(strict_runtime: bool) -> Vec<Check> {
    let mut out = Vec::new();

    let containerd_present = exists("/run/containerd/containerd.sock") || in_path("containerd");
    let containerd_status = if containerd_present {
        Status::Pass
    } else if strict_runtime {
        Status::Fail
    } else {
        Status::Unknown
    };
    out.push(Check::new(
        "containerd",
        containerd_status,
        if containerd_present {
            "containerd detected"
        } else {
            "containerd not detected"
        },
    ));

    out.push(containerd_systemdcgroup_check());

    for bin in ["runc", "ctr"] {
        let present = in_path(bin);
        out.push(Check::new(
            &format!("runtime_{}", bin),
            if present {
                Status::Pass
            } else {
                Status::Unknown
            },
            if present { "present" } else { "missing" },
        ));
    }

    for dep in ["iscsiadm", "cryptsetup", "dmsetup"] {
        let present = in_path(dep);
        out.push(Check::new(
            &format!("csi_{}", dep),
            if present {
                Status::Pass
            } else {
                Status::Unknown
            },
            if present { "present" } else { "missing" },
        ));
    }

    out
}

/// bash: gate on `systemctl cat containerd` succeeding (a containerd unit
/// is actually installed) before judging SystemdCgroup at all -- no unit
/// means UNKNOWN "containerd-not-installed", never a false FAIL. When a
/// unit exists, `grep -Rqs 'SystemdCgroup[[:space:]]*=[[:space:]]*true'
/// /etc/containerd /etc` decides PASS/FAIL. Shelled out to `grep` directly
/// (same recursive-search semantics bash gets from the real tool) rather
/// than reimplementing a config parser -- this crate stays zero-dependency
/// by using system tools for the handful of checks that need one, same as
/// the pre-existing `sha256sum`/`chronyc` calls elsewhere in this crate.
fn containerd_systemdcgroup_check() -> Check {
    if !command_ok("systemctl", &["cat", "containerd"]) {
        return Check::new(
            "containerd_systemdcgroup",
            Status::Unknown,
            "containerd-not-installed",
        );
    }
    let enabled = command_ok(
        "grep",
        &[
            "-Rqs",
            "SystemdCgroup[[:space:]]*=[[:space:]]*true",
            "/etc/containerd",
            "/etc",
        ],
    );
    Check::new(
        "containerd_systemdcgroup",
        if enabled { Status::Pass } else { Status::Fail },
        if enabled { "enabled" } else { "not-enabled" },
    )
}
