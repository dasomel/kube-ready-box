//! Platform identity and version-compatibility placeholder checks.

use std::env;

use crate::fsutil::read;
use crate::json::{Check, Status};

pub fn run() -> Vec<Check> {
    let mut out = Vec::new();

    let arch = env::consts::ARCH;
    // bash: PASS only for x86_64/aarch64, UNKNOWN otherwise. The prior
    // Rust check was an unconditional PASS regardless of value -- a
    // fabricated PASS for a hypothetical unsupported arch. Fixed.
    let arch_ok = arch == "x86_64" || arch == "aarch64";
    out.push(Check::new(
        "architecture",
        if arch_ok {
            Status::Pass
        } else {
            Status::Unknown
        },
        arch,
    ));

    let os_id = read("/etc/os-release")
        .map(|content| {
            if content.contains("Ubuntu") {
                "ubuntu".to_string()
            } else {
                "unknown".to_string()
            }
        })
        .unwrap_or_else(|| "unknown".to_string());
    out.push(Check::new(
        "os",
        if os_id == "ubuntu" {
            Status::Pass
        } else {
            Status::Unknown
        },
        &os_id,
    ));

    out.push(provider_check());
    out.push(compatibility_stub(
        "kubernetes_compatibility",
        "KUBERNETES_VERSION",
        "version",
    ));
    out.push(compatibility_stub(
        "runtime_compatibility",
        "CONTAINERD_VERSION",
        "containerd",
    ));

    out
}

/// bash reads `VAGRANT_PROVIDER`/`PROVIDER` env vars (not DMI/virt
/// auto-detection -- there is no such logic in the canonical reference,
/// so none is invented here either) and checks against a known set.
fn provider_check() -> Check {
    let provider = env::var("VAGRANT_PROVIDER")
        .or_else(|_| env::var("PROVIDER"))
        .unwrap_or_else(|_| "unknown".to_string());
    let known = matches!(
        provider.as_str(),
        "virtualbox" | "vmware_desktop" | "vmware_fusion"
    );
    Check::new(
        "provider",
        if known { Status::Pass } else { Status::Unknown },
        &provider,
    )
}

/// bash always emits UNKNOWN for these two -- they record what was
/// *requested* (if anything) without judging compatibility, since that
/// judgment needs a real installed kubelet/runtime matrix this tool
/// doesn't have. Kept as explicit UNKNOWN stubs rather than silently
/// omitted, matching the canonical reference's own "not resolved yet, but
/// not silently missing either" posture.
fn compatibility_stub(id: &str, env_var: &str, label: &str) -> Check {
    match env::var(env_var) {
        Ok(v) if !v.is_empty() => Check::new(
            id,
            Status::Unknown,
            &format!("{}={} requires installed kubelet/runtime matrix", label, v),
        ),
        _ => Check::new(id, Status::Unknown, "version-not-selected"),
    }
}
