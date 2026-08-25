//! Filesystem/process primitives shared by every check module.
//!
//! `read()`/`exists()`/`is_mountpoint()` honor `KUBE_READY_VERIFIER_ROOT`
//! as a path prefix -- this exists ONLY so unit tests can point checks at
//! a crafted fixture tree (fake `/proc/modules`, `/sys/fs/cgroup/...`)
//! without needing root or real kernel state. It is not a production
//! feature; real invocations never set this env var, so `root_prefix()`
//! is empty and every path resolves exactly as written.

use std::{env, fs, path::Path, process};

fn root_prefix() -> String {
    env::var("KUBE_READY_VERIFIER_ROOT").unwrap_or_default()
}

fn rooted(path: &str) -> String {
    format!("{}{}", root_prefix(), path)
}

pub fn read(path: &str) -> Option<String> {
    fs::read_to_string(rooted(path)).ok()
}

pub fn exists(path: &str) -> bool {
    Path::new(&rooted(path)).exists()
}

/// Whether `path` is currently a mount point, per `/proc/mounts`'s second
/// (whitespace-separated) field. Existence of the directory alone does not
/// mean it's mounted (e.g. an unmounted `/sys/fs/bpf` still exists as a
/// bare directory) -- this is deliberately stricter than `exists()`.
pub fn is_mountpoint(path: &str) -> Option<bool> {
    read("/proc/mounts").map(|mounts| {
        mounts
            .lines()
            .filter_map(|l| l.split_whitespace().nth(1))
            .any(|mp| mp == path)
    })
}

/// The filesystem type of whatever is mounted at `path` (matched against
/// `/proc/mounts`'s second field), or None if `path` isn't a mount point
/// there / `/proc/mounts` is unreadable.
pub fn mount_fstype(path: &str) -> Option<String> {
    read("/proc/mounts").and_then(|mounts| {
        mounts.lines().find_map(|l| {
            let mut f = l.split_whitespace();
            let _device = f.next()?;
            let target = f.next()?;
            let fstype = f.next()?;
            if target == path {
                Some(fstype.to_string())
            } else {
                None
            }
        })
    })
}

/// Whether `name` is an executable file somewhere on `$PATH` -- the same
/// question `command -v name` answers, without invoking the binary (unlike
/// this crate's earlier pattern of running `name --version` just to test
/// presence, which assumes every binary supports that flag and actually
/// executes untrusted-ish binaries just to check they exist).
pub fn in_path(name: &str) -> bool {
    let path_var = match env::var("PATH") {
        Ok(p) => p,
        Err(_) => return false,
    };
    env::split_paths(&path_var).any(|dir| {
        let candidate = dir.join(name);
        candidate.is_file()
    })
}

/// Runs `name args...` and returns stdout if it exits successfully, None
/// otherwise (missing binary, non-zero exit, etc). Not root-prefixed --
/// this invokes real system commands, which isn't something a unit test
/// can safely fixture; command-based checks are exercised by the bash CLI
/// contract test on a real Linux host instead.
pub fn command_output(name: &str, args: &[&str]) -> Option<String> {
    process::Command::new(name)
        .args(args)
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).into_owned())
}

pub fn command_ok(name: &str, args: &[&str]) -> bool {
    process::Command::new(name)
        .args(args)
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}
