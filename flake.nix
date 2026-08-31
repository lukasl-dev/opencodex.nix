{
  description = "OpenCodex packaged for Nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/default";
    bun2nix = {
      url = "github:nix-community/bun2nix?ref=2.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
    };
  };

  nixConfig = {
    extra-substituters = [ "https://nix-community.cachix.org" ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  outputs =
    {
      self,
      nixpkgs,
      systems,
      bun2nix,
    }:
    let
      current = builtins.fromJSON (builtins.readFile ./VERSION.json);
      forEachSystem = nixpkgs.lib.genAttrs (import systems);
    in
    {
      packages = forEachSystem (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ bun2nix.overlays.default ];
          };
        in
        rec {
          default = opencodex;
          opencodex = pkgs.callPackage ./package.nix {
            inherit (current) version hash;
          };

          docs-md =
            let
              instance = self.lib.mkOpenCodex { inherit pkgs; };
              docs = pkgs.nixosOptionsDoc {
                options = builtins.removeAttrs instance.options [ "_module" ];
              };
            in
            pkgs.runCommand "opencodex-options.md" { } ''
              mkdir -p $out
              cp ${docs.optionsCommonMark} $out/index.md
            '';
        }
      );

      checks = forEachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          package = self.packages.${system}.opencodex;
          configured = self.lib.mkOpenCodex {
            inherit pkgs;
            modules = [
              {
                opencodex.settings = {
                  port = 19138;
                  hostname = "127.0.0.1";
                };
              }
            ];
          };
        in
        {
          package = pkgs.runCommand "opencodex-package-check" { nativeBuildInputs = [ package ]; } ''
            ocx --version | grep -F ${nixpkgs.lib.escapeShellArg "opencodex ${current.version}"}
            opencodex --version | grep -F ${nixpkgs.lib.escapeShellArg "opencodex ${current.version}"}
            touch $out
          '';

          settings =
            pkgs.runCommand "opencodex-settings-check"
              {
                nativeBuildInputs = [
                  configured.settingsCommand
                  pkgs.jq
                ];
              }
              ''
                export HOME="$TMPDIR/home"
                export OPENCODEX_HOME="$TMPDIR/opencodex"
                export CODEX_HOME="$TMPDIR/codex"
                mkdir -p "$HOME" "$OPENCODEX_HOME" "$CODEX_HOME"

                opencodex-apply-settings
                jq -e \
                  '.port == 19138 and .hostname == "127.0.0.1" and (.providers.openai != null)' \
                  "$OPENCODEX_HOME/config.json"
                touch $out
              '';
        }
      );

      lib = import ./lib.nix {
        inherit self;
        inherit (nixpkgs) lib;
      };

      nixosModules = rec {
        default = opencodex;
        opencodex = import ./module.nix { inherit self; };
      };

      homeModules = rec {
        default = opencodex;
        opencodex = import ./home-manager.nix { inherit self; };
      };
      homeManagerModules = self.homeModules;

      overlays.default = _final: prev: {
        opencodex = self.packages.${prev.stdenv.hostPlatform.system}.opencodex;
      };

      apps = forEachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          update = import ./update.nix {
            inherit pkgs;
            bun2nix = bun2nix.packages.${system}.bun2nix;
          };
        in
        {
          update = {
            type = "app";
            program = "${update}/bin/opencodex-update";
            meta.description = "Update the packaged OpenCodex release";
          };
        }
      );

      formatter = forEachSystem (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
