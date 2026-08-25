//! gVisor/Kata sandbox-runtime capability detection.
//!
//! Absence is not a failure on a non-sandbox node by default -- these stay
//! UNKNOWN-only unless the caller explicitly opts in via `--require-sandbox`
//! (mirrors `--strict-runtime`'s opt-in-to-strictness pattern), matching
//! issue #12's own scope text: "sandbox capability detection", not
//! "sandbox capability enforcement".

use crate::fsutil::{exists, in_path};
use crate::json::{Check, Status};

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Require {
    None,
    Gvisor,
    Kata,
}

pub fn run(require: Require) -> Vec<Check> {
    let runsc = in_path("runsc") || exists("/usr/local/bin/runsc") || exists("/usr/bin/runsc");
    let kata = in_path("kata-runtime") || exists("/usr/bin/kata-runtime");

    let runsc_status = if runsc {
        Status::Pass
    } else if require == Require::Gvisor {
        Status::Fail
    } else {
        Status::Unknown
    };
    let kata_status = if kata {
        Status::Pass
    } else if require == Require::Kata {
        Status::Fail
    } else {
        Status::Unknown
    };

    vec![
        Check::new("sandbox_runsc", runsc_status, "gVisor runsc capability"),
        Check::new("sandbox_kata", kata_status, "Kata Containers capability"),
    ]
}
