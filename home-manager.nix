{ self }:
{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.programs.opencodex;
  service = cfg.service;
  serviceLauncher = pkgs.writeShellScript "opencodex-service" ''
    export PATH=${
      lib.escapeShellArg (lib.makeBinPath ([ config.home.profileDirectory ] ++ service.path))
    }:$PATH
    exec ${lib.getExe cfg.finalPackage} start --port ${toString service.port}
  '';
in
{
  imports = [
    (import ./options.nix {
      inherit self;
      optionPath = [
        "programs"
        "opencodex"
      ];
    })
  ];

  options.programs.opencodex.enable = lib.mkEnableOption "OpenCodex";

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        home.packages = [ cfg.finalPackage ];
      }

      (lib.mkIf service.enable {
        assertions = [
          {
            assertion = pkgs.stdenv.hostPlatform.isLinux;
            message = "the declarative OpenCodex Home Manager service currently requires Linux/systemd";
          }
        ];

        systemd.user.services.opencodex-proxy = {
          Unit = {
            Description = "OpenCodex provider proxy";
            After = [ "network-online.target" ];
            Wants = [ "network-online.target" ];
          };

          Service = {
            Type = "simple";
            Environment = [
              "HOME=${config.home.homeDirectory}"
              "OCX_SERVICE=1"
            ];
            ExecStartPre = lib.optional (cfg.settingsCommand != null) (lib.getExe cfg.settingsCommand);
            ExecStart = serviceLauncher;
            Restart = "on-failure";
            RestartSec = service.restartSec;
            UMask = "0077";
          };

          Install.WantedBy = [ "default.target" ];
        };
      })
    ]
  );
}
