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
          server = self.packages.${system}.server;
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

          # Regenerate drizzle/*.sql migrations against the currently-built
          # server's schema.js. Run this after bumping version/hashes in
          # package/default.nix. See drizzle/README.md for the full workflow.
          #
          # Usage: nix run .#generate-migration -- <short-description>
          # Example: nix run .#generate-migration -- add-teams
          generate-migration = {
            type = "app";
            program = toString (pkgs.writeShellScript "rybbix-generate-migration" ''
              set -euo pipefail
              NAME="''${1:-bump}"
              SCHEMA="${server}/lib/rybbit-server/dist/db/postgres/schema.js"
              OUT_DIR="$PWD/drizzle"

              if [ ! -f "$SCHEMA" ]; then
                echo "error: schema.js not found at $SCHEMA" >&2
                echo "Make sure nix build .#server succeeded." >&2
                exit 1
              fi
              if [ ! -d "$OUT_DIR/meta" ]; then
                echo "error: $OUT_DIR/meta not found — are you running from the flake root?" >&2
                exit 1
              fi

              TMPCONFIG=$(mktemp --suffix=.mjs)
              trap 'rm -f "$TMPCONFIG"' EXIT
              cat > "$TMPCONFIG" <<EOF
              import { defineConfig } from "drizzle-kit";
              export default defineConfig({
                dialect: "postgresql",
                schema: "$SCHEMA",
                out: "$OUT_DIR",
              });
              EOF

              cd "${server}/lib/rybbit-server"
              export NODE_PATH="${server}/lib/rybbit-server/node_modules"
              "${pkgs.nodejs_24}/bin/node" ./node_modules/.bin/drizzle-kit generate \
                --config "$TMPCONFIG" --name "$NAME"

              echo
              echo "Review the new files in $OUT_DIR and commit them alongside"
              echo "the version bump in package/default.nix."
            '');
          };
        }
      );

      formatter = forAllSystems (system: (pkgsFor system).nixfmt);
    };
}
