//! Minimal, dependency-free JSON building shared by every subcommand.
//! No serde: this crate is intentionally zero-dependency (see README.md),
//! and the output shape is small/flat enough that hand-built JSON is safe
//! as long as every string goes through `esc()`.

/// Every subcommand shares this one schema name (only `kind` distinguishes
/// what's being reported) -- already reserved for this crate in
/// docs/evidence-contracts.md.
pub const SCHEMA: &str = "kube-ready-evidence/v1";

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Status {
    Pass,
    Fail,
    Unknown,
    #[allow(dead_code)]
    Skip,
}

impl Status {
    pub fn as_str(self) -> &'static str {
        match self {
            Status::Pass => "PASS",
            Status::Fail => "FAIL",
            Status::Unknown => "UNKNOWN",
            Status::Skip => "SKIP",
        }
    }
}

pub fn esc(s: &str) -> String {
    s.replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
}

pub struct Check {
    pub id: String,
    pub status: Status,
    pub detail: String,
}

impl Check {
    pub fn new(id: &str, status: Status, detail: &str) -> Self {
        Check {
            id: id.to_string(),
            status,
            detail: detail.to_string(),
        }
    }

    pub fn to_json(&self) -> String {
        format!(
            "{{\"id\":\"{}\",\"status\":\"{}\",\"detail\":\"{}\"}}",
            esc(&self.id),
            self.status.as_str(),
            esc(&self.detail)
        )
    }
}

/// A run FAILs if any check FAILs. UNKNOWN never fails a run on its own --
/// matching every bash evidence script in this repo (CLAUDE.md: "UNKNOWN
/// never treated as healthy" for the *caller's* judgment, but it is not the
/// same as FAIL either; forcing a FAIL on UNKNOWN belongs to the caller as
/// an opt-in policy, e.g. `--strict-runtime`/`--require-sandbox`, not to
/// this shared helper).
pub fn any_fail(checks: &[Check]) -> bool {
    checks.iter().any(|c| c.status == Status::Fail)
}

pub fn checks_to_json(checks: &[Check]) -> String {
    checks
        .iter()
        .map(Check::to_json)
        .collect::<Vec<_>>()
        .join(",")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn esc_escapes_backslash_quote_newline() {
        assert_eq!(esc("a\\b\"c\nd"), "a\\\\b\\\"c\\nd");
    }

    #[test]
    fn esc_empty_string() {
        assert_eq!(esc(""), "");
    }

    #[test]
    fn any_fail_true_when_one_fails() {
        let checks = vec![
            Check::new("a", Status::Pass, ""),
            Check::new("b", Status::Fail, ""),
            Check::new("c", Status::Unknown, ""),
        ];
        assert!(any_fail(&checks));
    }

    #[test]
    fn any_fail_false_when_only_pass_and_unknown() {
        let checks = vec![
            Check::new("a", Status::Pass, ""),
            Check::new("c", Status::Unknown, ""),
        ];
        assert!(!any_fail(&checks));
    }
}
