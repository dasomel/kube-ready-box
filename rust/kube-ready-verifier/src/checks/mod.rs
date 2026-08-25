pub mod node_baseline;
pub mod platform;
pub mod runtime;
pub mod sandbox;
pub mod security_time;

use std::env;

use crate::json::{any_fail, checks_to_json, Check, SCHEMA};
use sandbox::Require;

pub struct PreflightOptions {
    pub strict_runtime: bool,
    pub require_sandbox: Require,
}

pub fn all_checks(opts: &PreflightOptions) -> Vec<Check> {
    let mut checks = Vec::new();
    checks.extend(node_baseline::run());
    checks.extend(runtime::run(opts.strict_runtime));
    checks.extend(security_time::run());
    checks.extend(sandbox::run(opts.require_sandbox));
    checks.extend(platform::run());
    checks
}

/// Runs every check group, prints the aggregated `kube-ready-evidence/v1`
/// `node-preflight` document, and returns the process exit code.
pub fn preflight(opts: PreflightOptions) -> i32 {
    let checks = all_checks(&opts);
    let fail = any_fail(&checks);
    let arch = env::consts::ARCH;
    println!(
        "{{\"schema\":\"{}\",\"kind\":\"node-preflight\",\"status\":\"{}\",\"platform\":\"linux/{}\",\"checks\":[{}]}}",
        SCHEMA,
        if fail { "FAIL" } else { "PASS" },
        arch,
        checks_to_json(&checks)
    );
    if fail {
        1
    } else {
        0
    }
}
