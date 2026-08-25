mod checks;
mod fsutil;
mod json;
mod verify_evidence;
mod verify_sha256;

use std::{env, process};

use checks::sandbox::Require;
use checks::PreflightOptions;

fn help() {
    println!(
        "kube-ready-verifier\n\n\
         USAGE:\n  \
         kube-ready-verifier preflight [--strict-runtime] [--require-sandbox=gvisor|kata]\n  \
         kube-ready-verifier verify-sha256 <SHA256SUMS>\n  \
         kube-ready-verifier verify-evidence <release-dir>\n\n\
         All verification commands are offline and require no package manager."
    );
}

fn parse_require_sandbox(args: &[String]) -> Require {
    for a in args {
        if let Some(v) = a.strip_prefix("--require-sandbox=") {
            return match v {
                "gvisor" => Require::Gvisor,
                "kata" => Require::Kata,
                _ => Require::None,
            };
        }
    }
    Require::None
}

fn main() {
    let all_args: Vec<String> = env::args().skip(1).collect();
    let cmd = all_args.first().cloned().unwrap_or_default();
    let sub_args: &[String] = if all_args.is_empty() {
        &[]
    } else {
        &all_args[1..]
    };

    let code = match cmd.as_str() {
        "preflight" => {
            let opts = PreflightOptions {
                strict_runtime: sub_args.iter().any(|x| x == "--strict-runtime"),
                require_sandbox: parse_require_sandbox(sub_args),
            };
            checks::preflight(opts)
        }
        "verify-sha256" => {
            let path = sub_args.first().cloned().unwrap_or_default();
            verify_sha256::run(&path)
        }
        "verify-evidence" => {
            let dir = sub_args.first().cloned().unwrap_or_default();
            verify_evidence::run(&dir)
        }
        "help" | "--help" | "" => {
            help();
            0
        }
        _ => {
            help();
            2
        }
    };
    process::exit(code);
}
