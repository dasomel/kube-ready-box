# Production-oriented SSH/security overlay. Import this module for a hardened
# artifact; the default Vagrant profile remains intentionally convenient for CI.
{ config, lib, pkgs, ... }:
{
  services.openssh.settings = {
    PermitRootLogin = "no";
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
  };

  users.users.vagrant.openssh.authorizedKeys.keys = lib.mkForce [];
  security.sudo.wheelNeedsPassword = true;

  environment.etc."kube-ready/profile".text = "hardened\n";
}
