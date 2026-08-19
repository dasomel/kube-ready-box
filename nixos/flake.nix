{
  description = "dasomel Kubernetes-ready NixOS Vagrant box";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  inputs.nixos-generators.url = "github:nix-community/nixos-generators";
  inputs.nixos-generators.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, nixos-generators, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems f;
    in {
      packages = forAllSystems (system: {
        vagrant-virtualbox = nixos-generators.nixosGenerate {
          inherit system;
          format = "vagrant-virtualbox";
          modules = [ ./configuration.nix ];
        };
        vagrant-libvirt = nixos-generators.nixosGenerate {
          inherit system;
          format = "vagrant-libvirt";
          modules = [ ./configuration.nix ];
        };
      });
      checks = forAllSystems (system: {
        configuration = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ ./configuration.nix ];
        };
      });
    };
}
