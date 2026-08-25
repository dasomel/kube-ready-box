//! Kernel/cgroup/filesystem baseline checks. Parity target throughout this
//! module (and the other `checks/*` modules) is `tools/node-readiness-attest.sh`,
//! the richest existing bash preflight -- check ids, thresholds and
//! PASS/FAIL/UNKNOWN semantics are chosen to match it exactly, not
//! reinvented, so the two implementations can be compared directly.

use crate::fsutil::{exists, is_mountpoint, mount_fstype, read};
use crate::json::{Check, Status};

pub fn run() -> Vec<Check> {
    let mut out = Vec::new();

    let cgroup_v2 = exists("/sys/fs/cgroup/cgroup.controllers");
    out.push(Check::new(
        "cgroup_v2",
        if cgroup_v2 {
            Status::Pass
        } else {
            Status::Fail
        },
        "cgroup v2 controller file",
    ));

    let swap = swap_enabled();
    out.push(Check::new(
        "swap",
        if swap { Status::Fail } else { Status::Pass },
        if swap {
            "swap is enabled"
        } else {
            "swap disabled"
        },
    ));

    let modules = read("/proc/modules").unwrap_or_default();
    for m in ["overlay", "br_netfilter"] {
        let ok = module_loaded(&modules, m);
        out.push(Check::new(
            &format!("module_{}", m),
            if ok { Status::Pass } else { Status::Fail },
            if ok { "loaded" } else { "not loaded" },
        ));
    }
    // bash precedent (node-readiness-attest.sh) never FAILs on a missing
    // iscsi_tcp module -- it's UNKNOWN-only. The prior Rust implementation
    // fell back to `exists("/lib/modules")`, which is true on virtually
    // every Linux host regardless of module state -- a fabricated PASS,
    // not a real signal. Dropped.
    let iscsi = module_loaded(&modules, "iscsi_tcp");
    out.push(Check::new(
        "module_iscsi_tcp",
        if iscsi { Status::Pass } else { Status::Unknown },
        "iscsi_tcp module availability",
    ));

    // bash checks whether /sys/fs/bpf is actually MOUNTED (`mountpoint -q`),
    // not just that the kernel supports the bpf filesystem type -- and
    // treats "not mounted yet" as UNKNOWN, not FAIL (kubelet/CNI may mount
    // it later). The prior Rust check tested kernel compile-time support
    // via /proc/filesystems and FAILed if absent -- a different, stricter
    // question than what bash asks. Matched to bash's semantics here.
    let bpffs = is_mountpoint("/sys/fs/bpf").unwrap_or(false);
    out.push(Check::new(
        "bpffs",
        if bpffs { Status::Pass } else { Status::Unknown },
        if bpffs { "mounted" } else { "not-mounted" },
    ));

    for (id, path) in [
        ("sysctl_ip_forward", "/proc/sys/net/ipv4/ip_forward"),
        (
            "sysctl_bridge_nf_call_iptables",
            "/proc/sys/net/bridge/bridge-nf-call-iptables",
        ),
    ] {
        let ok = read(path).map(|x| x.trim() == "1").unwrap_or(false);
        out.push(Check::new(
            id,
            if ok { Status::Pass } else { Status::Fail },
            path,
        ));
    }

    out.push(network_tunable_check(
        "network_nf_conntrack_max",
        "/proc/sys/net/netfilter/nf_conntrack_max",
    ));
    out.push(network_tunable_check(
        "network_tcp_syncookies",
        "/proc/sys/net/ipv4/tcp_syncookies",
    ));

    out.push(nofile_check());
    out.push(filesystem_check());

    out
}

pub fn swap_enabled() -> bool {
    read("/proc/swaps")
        .map(|x| x.lines().skip(1).any(|l| !l.trim().is_empty()))
        .unwrap_or(false)
}

/// True if `name` appears as the first whitespace-separated field of any
/// line in `/proc/modules`'s content -- guards against e.g. "overlay2"
/// falsely matching a lookup for "overlay".
pub fn module_loaded(modules_content: &str, name: &str) -> bool {
    modules_content
        .lines()
        .any(|l| l.split_whitespace().next() == Some(name))
}

fn network_tunable_check(id: &str, path: &str) -> Check {
    match read(path) {
        Some(v) => Check::new(id, Status::Pass, v.trim()),
        None => Check::new(id, Status::Unknown, "missing"),
    }
}

/// Soft RLIMIT_NOFILE for this process, parsed from `/proc/self/limits`
/// (no `libc` crate needed to call `getrlimit` -- this crate stays
/// zero-dependency). bash reads `ulimit -n`, which reports the same value.
pub fn nofile_soft_limit() -> Option<u64> {
    read("/proc/self/limits").and_then(|content| {
        content.lines().find_map(|l| {
            if !l.starts_with("Max open files") {
                return None;
            }
            // "Max open files            1024                 4096                 files"
            l.split_whitespace().nth(3)?.parse::<u64>().ok()
        })
    })
}

fn nofile_check() -> Check {
    match nofile_soft_limit() {
        Some(n) if n >= 65536 => Check::new("nofile", Status::Pass, &n.to_string()),
        Some(n) => Check::new("nofile", Status::Unknown, &n.to_string()),
        None => Check::new("nofile", Status::Unknown, "unavailable"),
    }
}

fn filesystem_check() -> Check {
    match mount_fstype("/") {
        Some(fs) if fs == "ext4" || fs == "xfs" => Check::new("filesystem", Status::Pass, &fs),
        Some(fs) => Check::new("filesystem", Status::Fail, &fs),
        None => Check::new("filesystem", Status::Fail, "unknown"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn module_loaded_matches_exact_token() {
        let content = "overlay 139264 1 - Live 0x0000000000000000\nbr_netfilter 32768 0 - Live 0x0000000000000000\n";
        assert!(module_loaded(content, "overlay"));
        assert!(module_loaded(content, "br_netfilter"));
        assert!(!module_loaded(content, "iscsi_tcp"));
    }

    #[test]
    fn module_loaded_does_not_false_positive_on_prefix() {
        // "overlay2" must not satisfy a lookup for "overlay".
        let content = "overlay2 139264 1 - Live 0x0000000000000000\n";
        assert!(!module_loaded(content, "overlay"));
    }

    #[test]
    fn nofile_parses_soft_limit_column() {
        let sample = "Limit                     Soft Limit           Hard Limit           Units     \n\
                       Max cpu time              unlimited            unlimited            seconds   \n\
                       Max open files            65536                65536                files     \n";
        // Simulate the parse directly against a fixture string, mirroring
        // nofile_soft_limit()'s own line-matching logic.
        let n = sample
            .lines()
            .find_map(|l| {
                if !l.starts_with("Max open files") {
                    return None;
                }
                l.split_whitespace().nth(3)?.parse::<u64>().ok()
            })
            .unwrap();
        assert_eq!(n, 65536);
    }
}
