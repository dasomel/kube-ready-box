//! Security baseline (AppArmor/seccomp/auditd) and time-sync checks.

use crate::fsutil::{command_ok, command_output, exists, read};
use crate::json::{Check, Status};

pub fn run() -> Vec<Check> {
    vec![
        time_sync_check(),
        apparmor_check(),
        seccomp_check(),
        auditd_check(),
    ]
}

/// AppArmor enablement, read from the kernel module parameter (Y/N), not
/// bare `/sys/module/apparmor` directory existence. The bare-existence
/// check this replaced was a false-green: a loaded-but-disabled module
/// reported PASS purely from the directory being present, which could
/// disagree with the (now fixed) bash check on the same host (#44
/// C-06/T-021b). Enabled -> PASS, confirmed disabled -> FAIL (unconditional,
/// #44 D4), parameter unreadable (module absent/kernel lacks AppArmor) ->
/// UNKNOWN.
fn apparmor_check() -> Check {
    let raw = read("/sys/module/apparmor/parameters/enabled");
    let (status, detail) = classify_apparmor_enabled(raw.as_deref());
    Check::new("apparmor", status, detail)
}

fn classify_apparmor_enabled(raw: Option<&str>) -> (Status, &'static str) {
    match raw.map(|s| s.trim()) {
        Some("Y") => (Status::Pass, "enabled"),
        Some("N") => (Status::Fail, "disabled"),
        Some(_) => (Status::Unknown, "unexpected-value"),
        None => (Status::Unknown, "parameters-unreadable"),
    }
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn apparmor_enabled_is_pass() {
        let (status, detail) = classify_apparmor_enabled(Some("Y\n"));
        assert_eq!(status.as_str(), "PASS");
        assert_eq!(detail, "enabled");
    }

    #[test]
    fn apparmor_disabled_is_fail_not_unknown() {
        // #44 D4: a confirmed-disabled AppArmor on a capable kernel is FAIL,
        // never UNKNOWN or PASS.
        let (status, detail) = classify_apparmor_enabled(Some("N\n"));
        assert_eq!(status.as_str(), "FAIL");
        assert_eq!(detail, "disabled");
    }

    #[test]
    fn apparmor_unreadable_parameter_is_unknown() {
        // Module absent / kernel without AppArmor support: cannot determine.
        let (status, detail) = classify_apparmor_enabled(None);
        assert_eq!(status.as_str(), "UNKNOWN");
        assert_eq!(detail, "parameters-unreadable");
    }

    #[test]
    fn apparmor_unexpected_value_is_unknown() {
        let (status, detail) = classify_apparmor_enabled(Some("?\n"));
        assert_eq!(status.as_str(), "UNKNOWN");
        assert_eq!(detail, "unexpected-value");
    }

    /// Drives `apparmor_check()` itself (the file-reading path via
    /// `fsutil::read`/`KUBE_READY_VERIFIER_ROOT`), not only the pure
    /// `classify_apparmor_enabled` classifier -- proof that this crate's
    /// actual `/sys/module/apparmor/parameters/enabled` read produces the
    /// same PASS/FAIL/UNKNOWN as the bash deny fixtures in
    /// tools/tests/workload-security-classification-test.sh (#44 T-021b).
    /// Sequential sub-cases in one test (rather than separate #[test]
    /// functions) so the shared, process-global env var never races with
    /// itself under cargo's parallel test runner.
    #[test]
    fn apparmor_check_reads_fixture_root() {
        let root = std::env::temp_dir().join(format!(
            "kube-ready-verifier-apparmor-test-{}",
            std::process::id()
        ));
        let param_dir = root.join("sys/module/apparmor/parameters");
        std::fs::create_dir_all(&param_dir).expect("create fixture parameter dir");
        // SAFETY: this test never runs concurrently with another that reads
        // or writes KUBE_READY_VERIFIER_ROOT (only this function touches it
        // in this crate), and the whole scenario matrix runs sequentially
        // within this single #[test] body.
        unsafe {
            std::env::set_var("KUBE_READY_VERIFIER_ROOT", &root);
        }

        std::fs::write(param_dir.join("enabled"), "N\n").expect("write disabled fixture");
        let disabled = apparmor_check();
        assert_eq!(disabled.status.as_str(), "FAIL");
        assert_eq!(disabled.detail, "disabled");

        std::fs::write(param_dir.join("enabled"), "Y\n").expect("write enabled fixture");
        let enabled = apparmor_check();
        assert_eq!(enabled.status.as_str(), "PASS");
        assert_eq!(enabled.detail, "enabled");

        std::fs::remove_file(param_dir.join("enabled")).expect("remove fixture for unreadable case");
        let unreadable = apparmor_check();
        assert_eq!(unreadable.status.as_str(), "UNKNOWN");
        assert_eq!(unreadable.detail, "parameters-unreadable");

        // SAFETY: same single-writer justification as above.
        unsafe {
            std::env::remove_var("KUBE_READY_VERIFIER_ROOT");
        }
        let _ = std::fs::remove_dir_all(&root);
    }
}
