{ self, lib }:

{
  mkOpenCodex =
    {
      pkgs,
      modules ? [ ],
      extraSpecialArgs ? { },
    }:
    let
      evaluated = lib.evalModules {
        specialArgs = {
          inherit self pkgs;
        }
        // extraSpecialArgs;
        modules = [ (import ./options.nix { inherit self; }) ] ++ modules;
      };
    in
    {
      inherit (evaluated) config options;
      package = evaluated.config.opencodex.finalPackage;
      settingsCommand = evaluated.config.opencodex.settingsCommand;
      settingsFile = evaluated.config.opencodex.settingsFile;
    };
}
