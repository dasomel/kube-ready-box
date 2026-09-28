# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 dasomel
#
# NixOS VM Test — AppArmor (#44 T-022)
# Two-node test: 'enabled' verifies AppArmor is active and containerd profile
# enforcement works; 'disabled' verifies the AC-003 deny case with apparmor=0.

{ pkgs, lib, ... }:

let
  # Scripts from the repo, injected into the VM as /etc/kube-ready-tests/*.
  securityCheckScript = ../.. + "/security/workload-security-check.sh";
  preflightScript = ../preflight.sh;

  # D1: Overrides needed because the qemu-vm test harness provides its own
  # virtual disk/bootloader that conflicts with configuration.nix defaults.
  testOverrides = { lib, ... }: {
    # qemu-vm.nix manages its own GRUB/bootloader; our mkDefault GRUB config
    # would conflict with the test harness's virtual disk layout.
    boot.loader.grub.enable = lib.mkForce false;
    boot.loader.grub.device = lib.mkForce "";

    # qemu-vm.nix creates its own root filesystem; our bpffs entry is fine
    # but any real disk fileSystems would clash.
    fileSystems = lib.mkForce {
      "/sys/fs/bpf" = { device = "bpffs"; fsType = "bpf"; };
    };

    # runNixOSTest uses a read-only nixpkgs module; configuration.nix's
    # allowUnsupportedSystem conflicts with that read-only config.
    nixpkgs.config = lib.mkForce {};

    # The Vagrant-specific fstab activation script references symlink
    # behavior that doesn't apply inside the qemu test harness.
    system.activationScripts.vagrantMutableFstab = lib.mkForce "";
  };

  # Minimal OCI image for the containerd AppArmor test (C-12).
  busyboxImage = pkgs.dockerTools.buildImage {
    name = "localhost/test-busybox";
    tag = "latest";
    copyToRoot = pkgs.buildEnv {
      name = "test-root";
      paths = [ pkgs.busybox ];
    };
    # busybox alone has no /tmp; without it a failed write would not prove a denial.
    extraCommands = "mkdir -p tmp && chmod 1777 tmp";
    config.Cmd = [ "/bin/sh" ];
  };
in
pkgs.testers.runNixOSTest {
  name = "apparmor-vm";

  nodes.enabled = { config, pkgs, lib, ... }: {
    imports = [
      ../configuration.nix
      testOverrides
    ];
    # The driver names machines after hostName; configuration.nix sets one shared name.
    networking.hostName = lib.mkForce "enabled";

    # C-12 deny profile, declared the NixOS way: /etc/apparmor.d is a read-only store
    # link, so the test cannot write profiles there at runtime.
    security.apparmor.policies."test-deny-tmp".profile = ''
      #include <tunables/global>
      profile test-deny-tmp flags=(attach_disconnected,mediate_deleted) {
        #include <abstractions/base>
        file,
        deny /tmp/** w,
      }
    '';

    # Extra packages the test scripts need (python3 for workload-security-check.sh,
    # jq for JSON parsing, apparmor-utils for aa-status and apparmor_parser).
    environment.systemPackages = with pkgs; [
      python3
      jq
      apparmor-utils
      apparmor-parser
    ];

    # Inject repo scripts into the VM filesystem.
    environment.etc."kube-ready-tests/workload-security-check.sh" = {
      source = securityCheckScript;
      mode = "0755";
    };
    environment.etc."kube-ready-tests/preflight.sh" = {
      source = preflightScript;
      mode = "0755";
    };

    # Pre-load the OCI image so ctr can import it.
    environment.etc."kube-ready-tests/busybox.tar" = {
      source = busyboxImage;
      mode = "0644";
    };

    # Ensure containerd is running for the C-12 test.
    virtualisation.containerd.enable = lib.mkForce true;
    # D11: Docker gap tracked in #63 — do not test Docker here.
    virtualisation.docker.enable = lib.mkForce false;

    # Give the VM enough resources for containerd + AppArmor tests.
    virtualisation.memorySize = 2048;
    virtualisation.cores = 2;
  };

  nodes.disabled = { config, pkgs, lib, ... }: {
    imports = [
      ../configuration.nix
      testOverrides
    ];
    # The driver names machines after hostName; configuration.nix sets one shared name.
    networking.hostName = lib.mkForce "disabled";

    # AC-003: kernel-level AppArmor disable.
    boot.kernelParams = [ "apparmor=0" ];

    environment.systemPackages = with pkgs; [
      python3
      jq
    ];

    environment.etc."kube-ready-tests/workload-security-check.sh" = {
      source = securityCheckScript;
      mode = "0755";
    };
    environment.etc."kube-ready-tests/preflight.sh" = {
      source = preflightScript;
      mode = "0755";
    };

    virtualisation.docker.enable = lib.mkForce false;

    virtualisation.memorySize = 1024;
  };

  testScript = ''
    import json

    # ── Node 'enabled': AppArmor active ──────────────────────────────
    enabled.start()
    enabled.wait_for_unit("multi-user.target")

    # Basic kernel assertions
    enabled.succeed("test \"$(cat /sys/module/apparmor/parameters/enabled)\" = Y")
    enabled.succeed("grep -q apparmor /sys/kernel/security/lsm")

    # Run workload-security-check.sh and capture JSON
    security_json = enabled.succeed(
      "bash /etc/kube-ready-tests/workload-security-check.sh 2>&1 || true"
    )
    print(f"=== enabled: workload-security-check.sh ===\n{security_json}")
    security = json.loads(security_json.strip().split("\n")[-1])
    checks = {c["id"]: c for c in security["checks"]}
    assert checks["apparmor"]["status"] == "PASS", f"apparmor: {checks['apparmor']}"
    assert checks["mac_backend"]["status"] == "PASS", f"mac_backend: {checks['mac_backend']}"

    # Run preflight.sh and capture JSON
    preflight_json = enabled.succeed(
      "bash /etc/kube-ready-tests/preflight.sh 2>&1 || true"
    )
    print(f"=== enabled: preflight.sh ===\n{preflight_json}")
    preflight = json.loads(preflight_json.strip().split("\n")[-1])
    pf_checks = {c["id"]: c for c in preflight["checks"]}
    assert pf_checks["apparmor"]["status"] == "PASS", f"preflight apparmor: {pf_checks['apparmor']}"

    # ── C-12: containerd + AppArmor profile enforcement ──────────────
    enabled.wait_for_unit("containerd.service")

    # Import the OCI image into containerd
    enabled.succeed("ctr image import /etc/kube-ready-tests/busybox.tar")

    # Verify the profile is loaded
    enabled.succeed("aa-status --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert \"test-deny-tmp\" in d[\"profiles\"], list(d[\"profiles\"].keys())'")

    # Control: without the profile the same write succeeds, so a failure below is
    # attributable to the profile rather than the image or runtime.
    enabled.succeed(
      "ctr run --rm localhost/test-busybox:latest test-aa-control "
      "sh -c 'touch /tmp/allowed'"
    )

    # Confined run (the LSM-specific attr: the generic /proc/self/attr/current returns
    # EINVAL on a stacked-LSM kernel): the container's own attr must name the profile and the write must be
    # denied by it. Exit status is printed rather than asserted by ctr, since the write
    # is expected to fail.
    result = enabled.succeed(
      "ctr run --rm --apparmor-profile test-deny-tmp "
      "localhost/test-busybox:latest test-aa "
      "sh -c 'echo attr=$(cat /proc/self/attr/apparmor/current); touch /tmp/blocked 2>&1; echo rc=$?'"
    )
    print(f"=== C-12 confined run ===\n{result}")
    assert "attr=test-deny-tmp" in result, f"container not confined by test-deny-tmp: {result}"
    assert "rc=0" not in result, f"write to /tmp was not denied: {result}"
    assert "Permission denied" in result, f"write failed for a reason other than AppArmor: {result}"

    # ── Node 'disabled': AC-003 deny case ────────────────────────────
    disabled.start()
    disabled.wait_for_unit("multi-user.target")

    # Kernel parameter should disable AppArmor
    disabled.succeed("test \"$(cat /sys/module/apparmor/parameters/enabled 2>/dev/null || echo N)\" != Y")

    # Run workload-security-check.sh — apparmor must FAIL
    security_disabled_json = disabled.succeed(
      "bash /etc/kube-ready-tests/workload-security-check.sh 2>&1; true"
    )
    print(f"=== disabled: workload-security-check.sh ===\n{security_disabled_json}")
    sec_dis = json.loads(security_disabled_json.strip().split("\n")[-1])
    dis_checks = {c["id"]: c for c in sec_dis["checks"]}
    assert dis_checks["apparmor"]["status"] == "FAIL", \
      f"disabled apparmor must FAIL (AC-003): {dis_checks['apparmor']}"

    # Run preflight.sh — apparmor must FAIL
    preflight_disabled_json = disabled.succeed(
      "bash /etc/kube-ready-tests/preflight.sh 2>&1; true"
    )
    print(f"=== disabled: preflight.sh ===\n{preflight_disabled_json}")
    pf_dis = json.loads(preflight_disabled_json.strip().split("\n")[-1])
    pf_dis_checks = {c["id"]: c for c in pf_dis["checks"]}
    assert pf_dis_checks["apparmor"]["status"] == "FAIL", \
      f"disabled preflight apparmor must FAIL (AC-003): {pf_dis_checks['apparmor']}"
  '';
}
