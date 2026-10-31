mod checks;
mod fsutil;
mod json;
mod verify_evidence;
mod verify_sha256;

use std::{env, process};

use checks::sandbox::Require;
use checks::PreflightOptions;

const HELP: &str = "kube-ready-verifier\n\n\
USAGE:\n  \
kube-ready-verifier preflight [--strict-runtime] [--require-sandbox=gvisor|kata]\n  \
kube-ready-verifier verify-sha256 <SHA256SUMS>\n  \
kube-ready-verifier verify-evidence <release-dir>\n\n\
All verification commands are offline and require no package manager.";

fn help() {
    println!("{HELP}");
}

/// 사용법 오류: 메시지와 usage 를 stderr 로 내보내고 exit 2.
/// 오타 난 플래그가 조용히 무시되어 더 약한 게이트가 PASS 하는 일을 막는다.
fn usage_error(msg: &str) -> i32 {
    eprintln!("error: {msg}\n\n{HELP}");
    2
}

fn parse_require_sandbox(v: &str) -> Result<Require, String> {
    match v {
        "gvisor" => Ok(Require::Gvisor),
        "kata" => Ok(Require::Kata),
        _ => Err(format!(
            "invalid --require-sandbox value '{v}' (expected gvisor|kata)"
        )),
    }
}

fn parse_preflight_args(args: &[String]) -> Result<PreflightOptions, String> {
    let mut opts = PreflightOptions {
        strict_runtime: false,
        require_sandbox: Require::None,
    };
    for a in args {
        if a == "--strict-runtime" {
            opts.strict_runtime = true;
        } else if let Some(v) = a.strip_prefix("--require-sandbox=") {
            opts.require_sandbox = parse_require_sandbox(v)?;
        } else {
            return Err(format!("unrecognized argument '{a}' for preflight"));
        }
    }
    Ok(opts)
}

/// 위치 인자 하나만 받는 서브커맨드용: `-` 로 시작하는 인자는 모두 거부한다.
fn parse_single_positional(args: &[String], cmd: &str) -> Result<String, String> {
    if let Some(a) = args.iter().find(|a| a.starts_with('-')) {
        return Err(format!("unrecognized argument '{a}' for {cmd}"));
    }
    if args.len() > 1 {
        return Err(format!("{cmd} takes exactly one path, got {}", args.len()));
    }
    Ok(args.first().cloned().unwrap_or_default())
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
        "preflight" => match parse_preflight_args(sub_args) {
            Ok(opts) => checks::preflight(opts),
            Err(e) => usage_error(&e),
        },
        "verify-sha256" => match parse_single_positional(sub_args, "verify-sha256") {
            Ok(path) => verify_sha256::run(&path),
            Err(e) => usage_error(&e),
        },
        "verify-evidence" => match parse_single_positional(sub_args, "verify-evidence") {
            Ok(dir) => verify_evidence::run(&dir),
            Err(e) => usage_error(&e),
        },
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

#[cfg(test)]
mod tests {
    use super::*;

    fn v(a: &[&str]) -> Vec<String> {
        a.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn preflight_valid_flags() {
        let o =
            parse_preflight_args(&v(&["--strict-runtime", "--require-sandbox=gvisor"])).unwrap();
        assert!(o.strict_runtime);
        assert!(matches!(o.require_sandbox, Require::Gvisor));
        assert!(parse_preflight_args(&v(&[])).is_ok());
    }

    #[test]
    fn preflight_rejects_bad_sandbox_and_unknown_flag() {
        assert!(parse_preflight_args(&v(&["--require-sandbox=gvisr"])).is_err());
        assert!(parse_preflight_args(&v(&["--require-sandbox="])).is_err());
        assert!(parse_preflight_args(&v(&["--strict-runtme"])).is_err());
    }

    #[test]
    fn single_positional_rejects_flags() {
        assert_eq!(parse_single_positional(&v(&["x"]), "c").unwrap(), "x");
        assert!(parse_single_positional(&v(&["--bogus", "x"]), "c").is_err());
    }
}
