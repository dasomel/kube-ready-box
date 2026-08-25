//! Security baseline (AppArmor/seccomp/auditd) and time-sync checks.

use crate::fsutil::{command_ok, command_output, exists};
use crate::json::{Check, Status};

pub fn run() -> Vec<Check> {
    vec![
        time_sync_check(),
        apparmor_check(),
        seccomp_check(),
        auditd_check(),
    ]
}

/// bash: `[ -d /sys/module/apparmor ]` -- a bare path check, not a
/// functional `aa-status` probe. Matched exactly; this is already correct
/// (this was NOT among the "soft-only, never fails" bugs -- bash's own
/// canonical check is this same bare existence test, so there is nothing
/// to fix here beyond confirming the match).
fn apparmor_check() -> Check {
    let loaded = exists("/sys/module/apparmor");
    Check::new(
        "apparmor",
        if loaded {
            Status::Pass
        } else {
            Status::Unknown
        },
        if loaded { "loaded" } else { "not-loaded" },
    )
}

/// New check (bash has this; the prior Rust preflight didn't).
fn seccomp_check() -> Check {
    let available = command_output("cat", &["/proc/self/status"])
        .map(|s| s.lines().any(|l| l.starts_with("Seccomp:")))
        .unwrap_or(false);
    Check::new(
        "seccomp",
        if available {
            Status::Pass
        } else {
            Status::Unknown
        },
        if available {
            "kernel-interface"
        } else {
            "unavailable"
        },
    )
}

/// bash's literal source (`[ -S /run/auditd.sock ] || [ -f /run/auditd.pid
/// ] && add PASS || add UNKNOWN`) has a real operator-precedence bug: `&&`
/// binds tighter than `||`, so when the socket exists the whole expression
/// short-circuits true *before* either `add` call runs, meaning that
/// script silently never records an auditd check at all when the socket
/// is present. Fixing that bash script is out of scope for this pass (see
/// plan); this check reimplements the evidently-intended logic instead:
/// socket OR pid file present -> PASS "active", else UNKNOWN "not-active".
fn auditd_check() -> Check {
    let active = exists("/run/auditd.sock") || exists("/run/auditd.pid");
    Check::new(
        "auditd",
        if active {
            Status::Pass
        } else {
            Status::Unknown
        },
        if active { "active" } else { "not-active" },
    )
}

/// bash: gate on `systemctl is-active --quiet chrony` OR `chronyc tracking`
/// succeeding; if neither works, chrony isn't functioning -> FAIL. If
/// gated true, `chronyc tracking` output containing "Leap status: Normal"
/// -> PASS "synchronized", anything else -> UNKNOWN "chrony-present-not-
/// confirmed" (chrony is running but hasn't confirmed sync yet). The prior
/// Rust check only tested `exists("/run/chrony")` and could never FAIL
/// even when chrony was completely absent/inactive -- the clearest
/// instance of the "soft-only, never fails" bug class this pass fixes.
fn time_sync_check() -> Check {
    let active = command_ok("systemctl", &["is-active", "--quiet", "chrony"])
        || command_output("chronyc", &["tracking"]).is_some();
    if !active {
        return Check::new("time_sync", Status::Fail, "chrony-not-active");
    }
    let synchronized = command_output("chronyc", &["tracking"])
        .map(|out| {
            out.lines()
                .any(|l| l.contains("Leap status") && l.contains("Normal"))
        })
        .unwrap_or(false);
    if synchronized {
        Check::new("time_sync", Status::Pass, "synchronized")
    } else {
        Check::new("time_sync", Status::Unknown, "chrony-present-not-confirmed")
    }
}
