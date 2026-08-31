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
  userConfig = if service.user == null then null else config.users.users.${service.user} or null;
  home = if userConfig == null then "/" else userConfig.home;
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

  options.programs.opencodex = {
    enable = lib.mkEnableOption "OpenCodex";

    service.user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "User account under which the OpenCodex system service runs.";
      example = "lukas";
    };

    service.openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the OpenCodex service port in the NixOS firewall.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        environment.systemPackages = [ cfg.finalPackage ];
      }

      (lib.mkIf service.enable {
        assertions = [
          {
            assertion = service.user != null;
            message = "programs.opencodex.service.user must be set when the NixOS service is enabled";
          }
          {
            assertion = service.user == null || userConfig != null;
            message = "programs.opencodex.service.user must name a declared NixOS user";
          }
        ];

        networking.firewall.allowedTCPPorts = lib.optional service.openFirewall service.port;

        systemd.services.opencodex-proxy = {
          description = "OpenCodex provider proxy";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];

          path = service.path;
          environment = {
            HOME = home;
            OCX_SERVICE = "1";
          };

          preStart = lib.optionalString (cfg.settingsCommand != null) ''
            ${lib.getExe cfg.settingsCommand}
          '';

          serviceConfig = {
            Type = "simple";
            User = if service.user == null then "root" else service.user;
            WorkingDirectory = home;
            ExecStart = "${lib.getExe cfg.finalPackage} start --port ${toString service.port}";
            Restart = "on-failure";
            RestartSec = service.restartSec;
            UMask = "0077";
          };
        };
      })
    ]
  );
}
