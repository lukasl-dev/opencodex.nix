{
  self,
  optionPath ? [ "opencodex" ],
}:
{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (pkgs.stdenv.hostPlatform) system;
  cfg = lib.attrByPath optionPath { } config;
  defaultPackage = self.packages.${system}.opencodex;
in
{
  options = lib.setAttrByPath optionPath {
    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      description = "The OpenCodex package to install and run.";
    };

    environment = lib.mkOption {
      type =
        let
          nixPath = lib.types.addCheck lib.types.path builtins.isPath;
          taggedValue = lib.types.attrTag {
            file = lib.mkOption {
              type = lib.types.either lib.types.str nixPath;
              description = "File whose contents are exported at runtime.";
            };
            value = lib.mkOption {
              type = lib.types.str;
              description = "Literal value to export.";
            };
          };
          attrs = lib.types.submodule {
            freeformType = lib.types.attrsOf taggedValue;
          };
          checkedAttrs = lib.types.addCheck attrs (
            values: lib.all lib.isValidPosixName (builtins.attrNames values)
          );
        in
        lib.types.nullOr (lib.types.either lib.types.path checkedAttrs);
      default = null;
      description = ''
        Environment for OpenCodex. This may be a shell environment file, or an
        attribute set whose values use either `{ value = "..."; }` or
        `{ file = path; }`. File values are read at runtime and are suitable for
        secret-manager paths.
      '';
      example = lib.literalExpression ''
        {
          OPENCODEX_HOME.value = "/home/user/.opencodex";
          OPENCODEX_API_AUTH_TOKEN.file = config.sops.secrets.opencodex-api-token.path;
        }
      '';
    };

    settings = lib.mkOption {
      type = lib.types.nullOr lib.types.attrs;
      default = null;
      description = ''
        OpenCodex `config.json` settings. When the declarative service is
        enabled, these values are recursively merged over the current or
        default configuration, validated, and imported before every service
        start. Use environment-variable references for secrets rather than
        putting secrets in this option.
      '';
      example = lib.literalExpression ''
        {
          port = 10100;
          hostname = "127.0.0.1";
        }
      '';
    };

    service = {
      enable = lib.mkEnableOption "the declarative OpenCodex background service";

      port = lib.mkOption {
        type = lib.types.port;
        default = 10100;
        description = "TCP port pinned by the OpenCodex service.";
      };

      restartSec = lib.mkOption {
        type = lib.types.ints.positive;
        default = 5;
        description = "Delay in seconds before restarting a failed OpenCodex service.";
      };

      path = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = ''
          Additional packages placed on the service PATH. Add the Codex CLI (and
          any managed client CLIs OpenCodex must discover) here for a NixOS
          system service. Home Manager services also inherit the user profile PATH.
        '';
      };
    };

    finalPackage = lib.mkOption {
      type = lib.types.package;
      internal = true;
      readOnly = true;
    };

    settingsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      internal = true;
      readOnly = true;
    };

    settingsCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      internal = true;
      readOnly = true;
    };
  };

  config = lib.setAttrByPath optionPath (
    let
      envPrelude = lib.optionalString (cfg.environment != null) (
        if lib.isAttrs cfg.environment && !lib.isDerivation cfg.environment then
          lib.concatLines (
            lib.mapAttrsToList (
              name: value:
              if value ? file then
                ''export ${lib.escapeShellArg name}="$(cat ${lib.escapeShellArg "${value.file}"})"''
              else
                "export ${lib.escapeShellArg name}=${lib.escapeShellArg value.value}"
            ) cfg.environment
          )
        else
          ''
            set -a
            . ${lib.escapeShellArg "${cfg.environment}"}
            set +a
          ''
      );

      launcher = pkgs.writeShellScriptBin "ocx" ''
        ${envPrelude}
        exec ${lib.escapeShellArg (lib.getExe cfg.package)} "$@"
      '';

      wrappedPackage = pkgs.symlinkJoin {
        name = "opencodex-wrapped";
        paths = [ launcher ];
        postBuild = ''
          ln -s ocx $out/bin/opencodex
        '';
        meta = cfg.package.meta // {
          mainProgram = "ocx";
        };
      };

      settingsFile =
        if cfg.settings == null then
          null
        else
          pkgs.writeText "opencodex-settings.json" (builtins.toJSON cfg.settings);

      settingsCommand =
        if settingsFile == null then
          null
        else
          pkgs.writeShellScriptBin "opencodex-apply-settings" ''
            tmp="$(${pkgs.coreutils}/bin/mktemp)"
            trap '${pkgs.coreutils}/bin/rm -f "$tmp"' EXIT
            ${lib.getExe finalPackage} config export - \
              | ${lib.getExe pkgs.jq} -s '.[0] * .[1]' - ${lib.escapeShellArg "${settingsFile}"} > "$tmp"
            ${lib.getExe finalPackage} config import "$tmp" --yes
          '';

      finalPackage = if cfg.environment == null then cfg.package else wrappedPackage;
    in
    {
      inherit finalPackage settingsCommand settingsFile;
    }
  );
}
