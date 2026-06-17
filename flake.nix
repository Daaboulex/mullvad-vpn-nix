{
  description = "Mullvad VPN — declarative daemon, GUI prefs, upstream version pin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    std = {
      url = "github:Daaboulex/nix-packaging-standard?ref=v2.5.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.git-hooks.follows = "git-hooks";
    };
  };

  outputs =
    inputs@{
      flake-parts,
      self,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      imports = [ inputs.std.flakeModules.base ];

      flake.overlays.default = import ./overlay.nix;
      flake.nixosModules.default = import ./nixos-module.nix;
      flake.homeManagerModules.default = import ./hm-module.nix;

      perSystem =
        { system, pkgs, ... }:
        let
          pkgs' = pkgs.extend self.overlays.default;
        in
        {
          packages.mullvad-vpn = pkgs'.mullvad-vpn;
          packages.default = pkgs'.mullvad-vpn;

          # Instantiate both modules (enabled) so activation errors surface.
          checks.module-eval-nixos = inputs.std.lib.nixosModuleCheck {
            inherit (inputs) nixpkgs;
            inherit system;
            module = ./nixos-module.nix;
            config = {
              nixpkgs.overlays = [ self.overlays.default ];
              services.mullvad-vpn-declarative.enable = true;
            };
          };

          checks.module-eval-hm = inputs.std.lib.homeModuleCheck {
            inherit (inputs) nixpkgs home-manager;
            inherit system;
            module = ./hm-module.nix;
            config.programs.mullvad-vpn-gui.enable = true;
          };
        };
    };
}
