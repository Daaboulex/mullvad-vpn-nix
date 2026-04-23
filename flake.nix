{
  description = "Mullvad VPN — declarative daemon, GUI prefs, upstream version pin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      git-hooks,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor =
        system:
        import nixpkgs {
          localSystem.system = system;
          overlays = [ self.overlays.default ];
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          p = pkgsFor system;
        in
        {
          default = p.mullvad-vpn;
          inherit (p) mullvad-vpn;
        }
      );

      overlays.default = import ./overlay.nix;

      nixosModules.default = import ./nixos-module.nix;
      homeManagerModules.default = import ./hm-module.nix;

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);

      checks = forAllSystems (system: {
        pre-commit = git-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            nixfmt-rfc-style.enable = true;
            deadnix.enable = true;
            statix.enable = true;
            shellcheck.enable = true;
          };
        };
        build = self.packages.${system}.default;
      });

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShellNoCC {
            inherit (self.checks.${system}.pre-commit) shellHook;
            packages = with pkgs; [
              nil
              nixfmt-rfc-style
              jq
            ];
          };
        }
      );
    };
}
