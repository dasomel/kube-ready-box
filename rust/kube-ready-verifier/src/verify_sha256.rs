//! `verify-sha256 <SHA256SUMS>` -- offline checksum manifest verification.
//! Uses the host's `sha256sum` utility per line (no native digest
//! implementation, no network, no package manager).

use std::{io, process};

use crate::fsutil::read;
use crate::json::SCHEMA;

fn sha256_file(path: &str) -> io::Result<String> {
    let out = process::Command::new("sha256sum").arg(path).output()?;
    if !out.status.success() {
        return Err(io::Error::other("sha256sum failed"));
    }
    Ok(String::from_utf8_lossy(&out.stdout)
        .split_whitespace()
        .next()
        .unwrap_or("")
        .to_string())
}

pub fn run(path: &str) -> i32 {
    let text = match read(path) {
        Some(x) => x,
        None => {
            eprintln!("missing manifest: {}", path);
            return 2;
        }
    };

    let mut checked = 0usize;
    let mut failures = 0usize;
    let mut malformed = 0usize;

    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        match parse_manifest_line(line) {
            Some((digest, file)) => {
                checked += 1;
                match sha256_file(file) {
                    Ok(actual) if actual.eq_ignore_ascii_case(digest) => {}
                    _ => failures += 1,
                }
            }
            // A line that isn't blank/comment but also doesn't parse as
            // "64-hex-digest  filename" is corruption, not something to
            // silently skip -- the prior implementation `continue`d here
            // without counting it anywhere, so a truncated/corrupted
            // manifest could under-report `checked` and still return
            // overall PASS. bash's release-promote.sh validate_sha256sums()
            // treats any non-matching line as a hard failure; mirrored via
            // this new `malformed` counter forcing FAIL below.
            None => malformed += 1,
        }
    }

    let status = if failures == 0 && malformed == 0 {
        "PASS"
    } else {
        "FAIL"
    };
    println!(
        "{{\"schema\":\"{}\",\"kind\":\"artifact-verification\",\"status\":\"{}\",\"checked\":{},\"failures\":{},\"malformed\":{},\"network\":false}}",
        SCHEMA, status, checked, failures, malformed
    );
    if status == "PASS" {
        0
    } else {
        1
    }
}

/// Parses one non-blank, non-comment manifest line as `(digest, filename)`.
/// A valid line is a 64-character lowercase-or-uppercase hex digest,
/// whitespace, then a non-empty filename -- matching bash's ERE
/// `^[0-9a-f]{64}[ *][ ]?\S` in spirit (case-insensitive hex is accepted
/// here since `eq_ignore_ascii_case` is used for the actual comparison;
/// bash's regex is lowercase-only in `release-promote.sh`, which this
/// crate's `verify-evidence` subcommand matches exactly for the
/// release-evidence file family specifically -- this looser check is for
/// the general-purpose `sha256sum`-style manifest this subcommand has
/// always accepted).
pub fn parse_manifest_line(line: &str) -> Option<(&str, &str)> {
    let mut parts = line.splitn(2, char::is_whitespace);
    let digest = parts.next()?;
    let rest = parts.next()?.trim_start();
    if digest.len() != 64 || !digest.chars().all(|c| c.is_ascii_hexdigit()) {
        return None;
    }
    let file = rest.trim_start_matches('*');
    if file.is_empty() {
        return None;
    }
    Some((digest, file))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn valid_line_parses() {
        let line = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  payload.bin";
        let (digest, file) = parse_manifest_line(line).unwrap();
        assert_eq!(digest.len(), 64);
        assert_eq!(file, "payload.bin");
    }

    #[test]
    fn binary_marker_asterisk_is_stripped() {
        let line = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 *payload.bin";
        let (_, file) = parse_manifest_line(line).unwrap();
        assert_eq!(file, "payload.bin");
    }

    #[test]
    fn uppercase_hex_still_parses_here() {
        let line = "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855  payload.bin";
        assert!(parse_manifest_line(line).is_some());
    }

    #[test]
    fn short_digest_is_malformed() {
        let line = "deadbeef  payload.bin";
        assert!(parse_manifest_line(line).is_none());
    }

    #[test]
    fn long_digest_is_malformed() {
        let line =
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855ff  payload.bin";
        assert!(parse_manifest_line(line).is_none());
    }

    #[test]
    fn missing_filename_is_malformed() {
        let line = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855   ";
        assert!(parse_manifest_line(line).is_none());
    }

    #[test]
    fn non_hex_digest_is_malformed() {
        let line = "g3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  payload.bin";
        assert!(parse_manifest_line(line).is_none());
    }
}
