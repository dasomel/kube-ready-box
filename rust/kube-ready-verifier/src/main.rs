use std::{env, fs, io::{self, Read}, path::Path, process};

const SCHEMA: &str = "kube-ready-evidence/v1";

#[derive(Clone, Copy)]
enum Status { Pass, Fail, Unknown, Skip }
impl Status { fn as_str(self) -> &'static str { match self { Status::Pass=>"PASS", Status::Fail=>"FAIL", Status::Unknown=>"UNKNOWN", Status::Skip=>"SKIP" } } }

fn read(path: &str) -> Option<String> { fs::read_to_string(path).ok() }
fn exists(path: &str) -> bool { Path::new(path).exists() }
fn command(name: &str) -> bool { process::Command::new(name).arg("--version").output().map(|x| x.status.success()).unwrap_or(false) }
fn check(id: &str, status: Status, detail: &str) -> String {
    format!("{{\"id\":\"{}\",\"status\":\"{}\",\"detail\":\"{}\"}}", esc(id), status.as_str(), esc(detail))
}
fn esc(s: &str) -> String { s.replace('\\', "\\\\").replace('"', "\\\"").replace('\n', "\\n") }

fn preflight(strict: bool) -> i32 {
    let mut results = Vec::new();
    let mut fail = false;
    let cgroup = read("/sys/fs/cgroup/cgroup.controllers").is_some();
    results.push(check("cgroup_v2", if cgroup {Status::Pass} else {Status::Fail}, "cgroup v2 controller file"));
    if !cgroup { fail = true; }

    let swap = read("/proc/swaps").map(|x| x.lines().skip(1).any(|l| !l.trim().is_empty())).unwrap_or(false);
    results.push(check("swap", if swap {Status::Fail} else {Status::Pass}, if swap {"swap is enabled"} else {"swap disabled"}));
    if swap { fail = true; }

    let modules = read("/proc/modules").unwrap_or_default();
    for m in ["overlay", "br_netfilter"] {
        let ok = modules.lines().any(|l| l.starts_with(&format!("{} ", m)));
        results.push(check(&format!("module_{}", m), if ok {Status::Pass} else {Status::Fail}, if ok {"loaded"} else {"not loaded"}));
        if !ok { fail = true; }
    }
    let iscsi = modules.lines().any(|l| l.starts_with("iscsi_tcp ")) || exists("/lib/modules");
    results.push(check("module_iscsi_tcp", if iscsi {Status::Pass} else {Status::Unknown}, "iscsi_tcp module availability"));

    let bpffs = read("/proc/filesystems").map(|x| x.lines().any(|l| l.contains("bpf"))).unwrap_or(false);
    results.push(check("bpffs", if bpffs {Status::Pass} else {Status::Fail}, "bpf filesystem support"));
    if !bpffs { fail = true; }

    for (id, path) in [("sysctl_ip_forward", "/proc/sys/net/ipv4/ip_forward"), ("sysctl_bridge_nf_call_iptables", "/proc/sys/net/bridge/bridge-nf-call-iptables")] {
        let ok = read(path).map(|x| x.trim() == "1").unwrap_or(false);
        results.push(check(id, if ok {Status::Pass} else {Status::Fail}, path));
        if !ok { fail = true; }
    }

    let containerd = exists("/run/containerd/containerd.sock") || command("containerd");
    let runtime_status = if containerd {Status::Pass} else if strict {Status::Fail} else {Status::Unknown};
    results.push(check("containerd", runtime_status, if containerd {"containerd detected"} else {"containerd not detected"}));
    if strict && !containerd { fail = true; }

    for (id, path) in [("apparmor", "/sys/module/apparmor"), ("auditd", "/var/run/auditd.pid"), ("chrony", "/run/chrony") ] {
        results.push(check(id, if exists(path) {Status::Pass} else {Status::Unknown}, path));
    }
    let runsc = command("runsc") || exists("/usr/local/bin/runsc") || exists("/usr/bin/runsc");
    let kata = command("kata-runtime") || exists("/usr/bin/kata-runtime");
    results.push(check("sandbox_runsc", if runsc {Status::Pass} else {Status::Unknown}, "gVisor runsc capability"));
    results.push(check("sandbox_kata", if kata {Status::Pass} else {Status::Unknown}, "Kata Containers capability"));

    let root = read("/etc/os-release").unwrap_or_default();
    let arch = env::consts::ARCH;
    results.push(check("platform", Status::Pass, &format!("linux/{}", arch)));
    let os = if root.contains("Ubuntu") {"ubuntu"} else {"unknown"};
    results.push(check("os", if os == "ubuntu" {Status::Pass} else {Status::Unknown}, os));

    println!("{{\"schema\":\"{}\",\"kind\":\"node-preflight\",\"status\":\"{}\",\"platform\":\"linux/{}\",\"checks\":[{}]}}", SCHEMA, if fail {"FAIL"} else {"PASS"}, arch, results.join(","));
    if fail {1} else {0}
}

fn sha256_file(path: &str) -> io::Result<String> {
    // FIPS-friendly/offline verification uses the host's sha256sum utility; no network or package manager is invoked.
    let out = process::Command::new("sha256sum").arg(path).output()?;
    if !out.status.success() { return Err(io::Error::new(io::ErrorKind::Other, "sha256sum failed")); }
    Ok(String::from_utf8_lossy(&out.stdout).split_whitespace().next().unwrap_or("").to_string())
}

fn verify_manifest(path: &str) -> i32 {
    let text = match read(path) { Some(x)=>x, None=>{ eprintln!("missing manifest: {}", path); return 2; } };
    let mut checked=0usize; let mut failures=0usize;
    for line in text.lines() {
        let line=line.trim(); if line.is_empty() || line.starts_with('#') {continue;}
        let mut p=line.split_whitespace(); let digest=p.next().unwrap_or(""); let file=p.next().unwrap_or("");
        if digest.len()!=64 || file.is_empty() { continue; }
        checked+=1;
        match sha256_file(file) { Ok(actual) if actual.eq_ignore_ascii_case(digest)=>{}, _=>failures+=1 }
    }
    println!("{{\"schema\":\"{}\",\"kind\":\"artifact-verification\",\"status\":\"{}\",\"checked\":{},\"failures\":{},\"network\":false}}", SCHEMA, if failures==0 {"PASS"} else {"FAIL"}, checked, failures);
    if failures==0 {0} else {1}
}

fn help() { println!("kube-ready-verifier\n\nUSAGE:\n  kube-ready-verifier preflight [--strict-runtime]\n  kube-ready-verifier verify-sha256 <SHA256SUMS>\n\nAll verification commands are offline and require no package manager."); }

fn main() {
    let mut args=env::args().skip(1); let cmd=args.next().unwrap_or_default();
    let code=match cmd.as_str() { "preflight"=>preflight(args.any(|x|x=="--strict-runtime")), "verify-sha256"=>verify_manifest(&args.next().unwrap_or_default()), "help"|"--help"|""=>{help();0}, _=>{help();2} };
    process::exit(code);
}
