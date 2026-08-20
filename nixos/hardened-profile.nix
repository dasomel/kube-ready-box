# Production-oriented SSH/security overlay (#9).
# 기본 Vagrant 프로파일은 CI 편의를 위해 insecure key/password 로그인을 유지하고,
# 이 모듈을 import 한 아티팩트만 하드닝한다.
#
# 주의: 이 프로파일은 vagrant insecure key 를 제거한다. 대체 키를 주지 않으면
# 로그인 수단이 하나도 없는 이미지가 만들어지므로, assertion 으로 빌드를 실패시킨다.
# 키는 kubeReady.hardenedAuthorizedKeys 로 주입한다.
{ config, lib, pkgs, ... }:

with lib;

{
  options.kubeReady.hardenedAuthorizedKeys = mkOption {
    type = types.listOf types.str;
    default = [ ];
    description = ''
      하드닝 프로파일에서 vagrant 계정에 설치할 SSH 공개키 목록.
      비워두면 접근 불가능한 이미지가 되므로 빌드가 실패한다.
    '';
    example = [ "ssh-ed25519 AAAAC3Nz... admin@example.com" ];
  };

  options.kubeReady.hardenedPasswordHash = mkOption {
    type = types.nullOr types.str;
    default = null;
    description = ''
      vagrant 계정의 비밀번호 해시(mkpasswd -m sha-512). 지정하면 sudo 에 비밀번호를
      요구한다. null 이면 키 인증만으로 접근이 통제되므로 무암호 sudo 를 유지한다
      (비밀번호가 없는 상태에서 wheelNeedsPassword 를 켜면 sudo 가 아예 불가능해진다).
    '';
  };

  config = {
    assertions = [
      {
        assertion = config.kubeReady.hardenedAuthorizedKeys != [ ];
        message = ''
          hardened profile: kubeReady.hardenedAuthorizedKeys 가 비어 있습니다.
          이 프로파일은 vagrant insecure key 를 제거하고 password 인증을 끄므로,
          대체 공개키가 없으면 로그인할 수 없는 이미지가 만들어집니다.
          예: kubeReady.hardenedAuthorizedKeys = [ "ssh-ed25519 AAAA..." ];
        '';
      }
    ];

    # configuration.nix 가 같은 옵션을 정의하므로 mkForce 로 우선순위를 올려야 한다.
    # 그렇지 않으면 "conflicting definition values" 로 평가 자체가 실패한다.
    services.openssh.settings = {
      PermitRootLogin = mkForce "no";
      PasswordAuthentication = mkForce false;
      KbdInteractiveAuthentication = mkForce false;
    };

    users.users.vagrant.openssh.authorizedKeys.keys =
      mkForce config.kubeReady.hardenedAuthorizedKeys;

    # 비밀번호 해시가 주어진 경우에만 sudo 에 비밀번호를 요구한다.
    # 해시 없이 wheelNeedsPassword 를 켜면 sudo 가 불가능한 이미지가 된다.
    security.sudo.wheelNeedsPassword = mkForce (config.kubeReady.hardenedPasswordHash != null);
    users.users.vagrant.hashedPassword =
      mkIf (config.kubeReady.hardenedPasswordHash != null)
        config.kubeReady.hardenedPasswordHash;

    environment.etc."kube-ready/profile".text = "hardened\n";
  };
}
