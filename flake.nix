{
  description = "Rybbit - Privacy-focused analytics platform (Nix packaging)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          packages = pkgs.callPackage ./package { };
        in
        {
          inherit (packages) shared client server default;
        }
      );

      overlays = {
        default = self.overlays.rybbit;
        rybbit = _final: prev: {
          rybbit = prev.callPackage ./package { };
        };
      };

      nixosModules = {
        default = self.nixosModules.rybbit;
        rybbit =
          {
            config,
            lib,
            pkgs,
            ...
          }:
          let
            rybbitPkg = self.packages.${pkgs.system}.default;
          in
          {
            imports = [ ./module.nix ];
            config = lib.mkIf config.services.rybbit.enable {
              services.rybbit.package = lib.mkDefault rybbitPkg;
            };
          };
      };

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.callPackage ./shell.nix { };
        }
      );

      apps = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          update = import ./package/update.nix {
            inherit (pkgs)
              writeShellScript
              prefetch-npm-deps
              nix-prefetch-github
              gnused
              curl
              jq
              ;
          };
        }
      );

      formatter = forAllSystems (system: (pkgsFor system).nixfmt);
    };
}
