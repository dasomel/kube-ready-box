//! `verify-evidence <release-dir>` -- structural validation of the 5
//! release-evidence files `tools/release-promote.sh` requires
//! (verification.json, SHA256SUMS, sbom.json, security-report.json,
//! license-report.json), mirroring its `validate_sha256sums()`/
//! `validate_json()` logic exactly (same regex, same missing-file-is-
//! invalid rule) so the two validators can't silently drift apart.
//!
//! This is an INDEPENDENT additional cross-check, not a replacement for
//! release-promote.sh's own gate -- it does not touch release state, does
//! not implement matrix_eval()'s target-coverage logic, and does not
//! attempt signature/provenance verification (no signing infrastructure
//! exists in this repo yet). Two independently-written validators
//! agreeing raises confidence; this does not become the authoritative
//! gate.

use std::path::Path;
use std::process;

use crate::fsutil::read;
use crate::json::{esc, SCHEMA};

const EVIDENCE_FILES: &[&str] = &[
    "verification.json",
    "SHA256SUMS",
    "sbom.json",
    "security-report.json",
    "license-report.json",
];

pub fn run(release_dir: &str) -> i32 {
    let mut checks = Vec::new();
    let mut failures = 0usize;

    for name in EVIDENCE_FILES {
        let path = Path::new(release_dir).join(name);
        let path_str = path.to_string_lossy().into_owned();
        let (status, detail) = evidence_check(&path_str, name);
        if status == "FAIL" {
            failures += 1;
        }
        checks.push(format!(
            "{{\"id\":\"{}\",\"status\":\"{}\",\"detail\":\"{}\"}}",
            esc(name),
            status,
            esc(&detail)
        ));
    }

    let status = if failures == 0 { "PASS" } else { "FAIL" };
    println!(
        "{{\"schema\":\"{}\",\"kind\":\"release-evidence-verification\",\"status\":\"{}\",\"release_dir\":\"{}\",\"failures\":{},\"checks\":[{}]}}",
        SCHEMA,
        status,
        esc(release_dir),
        failures,
        checks.join(",")
    );
    if status == "PASS" {
        0
    } else {
        1
    }
}

fn evidence_check(path: &str, name: &str) -> (&'static str, String) {
    let content = match read(path) {
        Some(c) if !c.trim().is_empty() => c,
        _ => return ("FAIL", "missing".to_string()),
    };

    if name == "SHA256SUMS" {
        match validate_sha256sums(&content) {
            Ok(()) => ("PASS", String::new()),
            Err(detail) => ("FAIL", format!("invalid ({})", detail)),
        }
    } else {
        match validate_json(path) {
            Ok(()) => ("PASS", String::new()),
            Err(detail) => ("FAIL", format!("invalid JSON ({})", detail)),
        }
    }
}

/// Mirrors release-promote.sh's `validate_sha256sums()` exactly: every
/// non-blank line must match `^[0-9a-f]{64}[ *][ ]?\S` (lowercase hex
/// only -- unlike this crate's general-purpose `verify-sha256` subcommand,
/// which is intentionally more lenient; this one exists specifically to
/// agree with release-promote.sh's own regex, not to be a friendlier
/// checker).
pub fn validate_sha256sums(content: &str) -> Result<(), String> {
    for (idx, line) in content.lines().enumerate() {
        if line.trim().is_empty() {
            continue;
        }
        if !matches_sha256sums_line(line) {
            return Err(format!("line {}: {}", idx + 1, line));
        }
    }
    Ok(())
}

fn matches_sha256sums_line(line: &str) -> bool {
    let bytes = line.as_bytes();
    if bytes.len() < 66 {
        return false;
    }
    if !bytes[..64]
        .iter()
        .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(b))
    {
        return false;
    }
    match bytes[64] {
        b' ' | b'*' => {}
        _ => return false,
    }
    let mut rest = &line[65..];
    if let Some(stripped) = rest.strip_prefix(' ') {
        rest = stripped;
    }
    matches!(rest.chars().next(), Some(c) if !c.is_whitespace())
}

/// Shells out to `python3 -c "json.load(...)"`, matching
/// release-promote.sh's own validator exactly (same interpreter, same
/// error surface) rather than hand-rolling a JSON parser just for
/// validation -- this crate stays zero-dependency, and `python3` is
/// already an established dependency across this repo's tooling (see
/// CLAUDE.md), not a new one introduced here.
fn validate_json(path: &str) -> Result<(), String> {
    let out = process::Command::new("python3")
        .args(["-c", "import json,sys; json.load(open(sys.argv[1]))", path])
        .output();
    match out {
        Ok(o) if o.status.success() => Ok(()),
        Ok(o) => {
            let stderr = String::from_utf8_lossy(&o.stderr);
            let last_line = stderr.lines().last().unwrap_or("invalid JSON").to_string();
            Err(last_line)
        }
        Err(e) => Err(format!("python3 unavailable: {}", e)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn valid_sha256sums_content() {
        let content = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  a.txt\n\
                        e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 *b.bin\n";
        assert!(validate_sha256sums(content).is_ok());
    }

    #[test]
    fn uppercase_hex_is_rejected() {
        // release-promote.sh's regex is lowercase-only -- this must match
        // that, unlike verify_sha256's more lenient general parser.
        let content = "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B85  a.txt\n";
        assert!(validate_sha256sums(content).is_err());
    }

    #[test]
    fn short_hex_is_rejected() {
        let content = "deadbeef  a.txt\n";
        assert!(validate_sha256sums(content).is_err());
    }

    #[test]
    fn missing_filename_is_rejected() {
        let content = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855   \n";
        assert!(validate_sha256sums(content).is_err());
    }

    #[test]
    fn blank_lines_are_skipped() {
        let content =
            "\n   \ne3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  a.txt\n\n";
        assert!(validate_sha256sums(content).is_ok());
    }

    #[test]
    fn error_reports_correct_line_number() {
        let content =
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  a.txt\nbad-line\n";
        let err = validate_sha256sums(content).unwrap_err();
        assert!(err.starts_with("line 2:"));
    }
}
