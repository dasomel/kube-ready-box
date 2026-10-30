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
//!
//! Beyond structure, it mirrors release-promote.sh's content gates: the
//! status-bearing reports (security-report.json, license-report.json) must
//! carry status PASS (UNKNOWN only with ALLOW_UNKNOWN_EVIDENCE=1, missing
//! status is invalid), and every file SHA256SUMS lists must exist next to
//! it with a matching hash.

use std::path::Path;
use std::process;

use crate::fsutil::{command_output, in_path, read};
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
        let dir = match std::env::var_os("ARTIFACT_DIR") {
            Some(d) if !d.is_empty() => std::path::PathBuf::from(d),
            _ => Path::new(path)
                .parent()
                .unwrap_or_else(|| Path::new("."))
                .to_path_buf(),
        };
        match validate_sha256sums(&content)
            .and_then(|()| verify_sha256sums_hashes(&dir, &content, &hash_file))
        {
            Ok(()) => ("PASS", String::new()),
            Err(detail) => ("FAIL", format!("invalid ({})", detail)),
        }
    } else {
        if let Err(detail) = validate_json(path) {
            return ("FAIL", format!("invalid JSON ({})", detail));
        }
        if name == "security-report.json" || name == "license-report.json" {
            let allow = std::env::var("ALLOW_UNKNOWN_EVIDENCE").map_or(false, |v| v == "1");
            if let Err(detail) = check_report_status(report_status(path).as_deref(), allow) {
                return ("FAIL", detail);
            }
        }
        ("PASS", String::new())
    }
}

/// Mirrors release-promote.sh's status gate: only PASS passes; UNKNOWN is
/// never healthy and passes solely with the explicit opt-in; anything else
/// (FAIL, other values, missing field) fails.
pub fn check_report_status(status: Option<&str>, allow_unknown: bool) -> Result<(), String> {
    match status {
        Some("PASS") => Ok(()),
        Some("UNKNOWN") if allow_unknown => Ok(()),
        Some("UNKNOWN") => Err("status UNKNOWN (set ALLOW_UNKNOWN_EVIDENCE=1 to override)".into()),
        Some("") | None => Err("status field missing".into()),
        Some(other) => Err(format!("status {}", other)),
    }
}

fn report_status(path: &str) -> Option<String> {
    command_output(
        "python3",
        &[
            "-c",
            "import json,sys\nd=json.load(open(sys.argv[1]))\ns=d.get('status') if isinstance(d,dict) else None\nprint(s if isinstance(s,str) else '')",
            path,
        ],
    )
    .map(|o| o.trim_end_matches('\n').to_string())
}

fn hash_file(path: &Path) -> Result<String, String> {
    let p = path.to_string_lossy();
    let out = command_output("sha256sum", &["--", &p])
        .or_else(|| command_output("shasum", &["-a", "256", "--", &p]));
    match out {
        Some(o) => Ok(o.split_whitespace().next().unwrap_or("").to_string()),
        None if in_path("sha256sum") || in_path("shasum") => Err("hash tool failed".into()),
        None => Err("no sha256 tool available".into()),
    }
}

/// Mirrors release-promote.sh's `verify_sha256sums_hashes()`: each listed
/// file must resolve (symlinks followed) to a regular file under the real
/// `dir` (ARTIFACT_DIR, default the release dir) and hash to the listed value.
pub fn verify_sha256sums_hashes(
    dir: &Path,
    content: &str,
    hash: &dyn Fn(&Path) -> Result<String, String>,
) -> Result<(), String> {
    let base = dir
        .canonicalize()
        .map_err(|_| format!("artifact dir not found: {}", dir.display()))?;
    for line in content.lines() {
        if line.trim().is_empty() {
            continue;
        }
        let want = &line[..64];
        let mut name = &line[65..];
        if let Some(stripped) = name.strip_prefix(' ') {
            name = stripped;
        }
        // `sha256sum -b` 의 바이너리 마커 `*` 한 개를 제거한다.
        if let Some(stripped) = name.strip_prefix('*') {
            name = stripped;
        }
        if name.starts_with('/') || name.split('/').any(|c| c == "..") {
            return Err(format!("path escapes artifact dir: {}", name));
        }
        let joined = base.join(name);
        if !joined.exists() {
            return Err(format!(
                "listed file missing: {} (in {}; set ARTIFACT_DIR, e.g. ARTIFACT_DIR=packer/dist)",
                name,
                dir.display()
            ));
        }
        let target = joined
            .canonicalize()
            .map_err(|_| format!("listed file missing: {}", name))?;
        if !target.starts_with(&base) {
            return Err(format!("path escapes artifact dir: {}", name));
        }
        if !target.is_file() {
            return Err(format!("listed file missing: {} (not a regular file)", name));
        }
        match hash(&target) {
            Ok(got) if got == want => {}
            Ok(_) => return Err(format!("hash mismatch: {}", name)),
            Err(e) => return Err(e),
        }
    }
    Ok(())
}

/// Mirrors release-promote.sh's `validate_sha256sums()` exactly: every
/// non-blank line must match `^[0-9a-f]{64}[ *][ ]?\S` (lowercase hex
/// only -- unlike this crate's general-purpose `verify-sha256` subcommand,
/// which is intentionally more lenient). CRLF is rejected and at least one
/// entry is required, same as the bash gate.
pub fn validate_sha256sums(content: &str) -> Result<(), String> {
    if content.contains('\r') {
        return Err("contains CR (CRLF line endings not allowed)".into());
    }
    let mut entries = 0usize;
    for (idx, line) in content.lines().enumerate() {
        if line.trim().is_empty() {
            continue;
        }
        if !matches_sha256sums_line(line) {
            return Err(format!("line {}: {}", idx + 1, line));
        }
        entries += 1;
    }
    if entries == 0 {
        return Err("no entries".into());
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
/// validation -- this crate stays zero-dependency.
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

    #[test]
    fn report_status_gate() {
        assert!(check_report_status(Some("PASS"), false).is_ok());
        assert!(check_report_status(Some("FAIL"), true).is_err());
        assert!(check_report_status(Some("UNKNOWN"), false).is_err());
        assert!(check_report_status(Some("UNKNOWN"), true).is_ok());
        assert!(check_report_status(None, true).is_err());
        assert!(check_report_status(Some(""), true).is_err());
    }

    #[test]
    fn crlf_and_empty_sha256sums_rejected() {
        let l = format!("{}  a.txt\r\n", "a".repeat(64));
        assert!(validate_sha256sums(&l).unwrap_err().contains("CR"));
        assert_eq!(validate_sha256sums("  \n\n").unwrap_err(), "no entries");
    }

    #[test]
    fn sha256sums_hashes_checked() {
        let dir = std::env::temp_dir().join(format!("kre-hash-{}", std::process::id()));
        let out = std::env::temp_dir().join(format!("kre-out-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::create_dir_all(&out).unwrap();
        std::fs::write(dir.join("a.txt"), "x").unwrap();
        std::fs::write(out.join("secret"), "x").unwrap();
        let good = "a".repeat(64);
        let fake = |_: &Path| Ok("a".repeat(64));
        let line = format!("{}  a.txt\n", good);
        assert!(verify_sha256sums_hashes(&dir, &line, &fake).is_ok());
        // `*` 바이너리 마커
        let star = format!("{} *a.txt\n", good);
        assert!(verify_sha256sums_hashes(&dir, &star, &fake).is_ok());
        let bad = |_: &Path| Ok("b".repeat(64));
        assert!(verify_sha256sums_hashes(&dir, &line, &bad)
            .unwrap_err()
            .starts_with("hash mismatch"));
        let notool = |_: &Path| Err("no sha256 tool available".to_string());
        assert_eq!(
            verify_sha256sums_hashes(&dir, &line, &notool).unwrap_err(),
            "no sha256 tool available"
        );
        let missing = format!("{}  nope.txt\n", good);
        let err = verify_sha256sums_hashes(&dir, &missing, &fake).unwrap_err();
        assert!(err.starts_with("listed file missing") && err.contains("ARTIFACT_DIR"));
        for evil in ["../a.txt", "/etc/passwd", "sub/../../a.txt"] {
            let l = format!("{}  {}\n", good, evil);
            assert!(verify_sha256sums_hashes(&dir, &l, &fake)
                .unwrap_err()
                .starts_with("path escapes"));
        }
        // 심볼릭 링크 탈출: 파일 링크, 디렉터리 링크
        #[cfg(unix)]
        {
            std::os::unix::fs::symlink(out.join("secret"), dir.join("link")).unwrap();
            std::os::unix::fs::symlink(&out, dir.join("dlink")).unwrap();
            for evil in ["link", "dlink/secret"] {
                let l = format!("{}  {}\n", good, evil);
                assert!(verify_sha256sums_hashes(&dir, &l, &fake)
                    .unwrap_err()
                    .starts_with("path escapes"));
            }
        }
        std::fs::remove_dir_all(&dir).ok();
        std::fs::remove_dir_all(&out).ok();
    }

    #[test]
    fn status_is_not_trimmed() {
        assert!(check_report_status(Some(" PASS "), false).is_err());
    }
}
