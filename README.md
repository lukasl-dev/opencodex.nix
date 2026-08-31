# opencodex.nix

A Nix flake for [OpenCodex](https://github.com/lidge-jun/opencodex), the universal provider proxy for Codex.

It provides:

- a reproducible `ocx` / `opencodex` package
- NixOS and Home Manager modules
- declarative systemd services
- runtime-safe environment and secret-file wiring
- `lib.mkOpenCodex` for configured package wrappers

## Quick start

```sh
nix run github:lukasl-dev/opencodex.nix --accept-flake-config -- --version
```

## Home Manager

```nix
{
  inputs.opencodex.url = "github:lukasl-dev/opencodex.nix";

  imports = [ inputs.opencodex.homeModules.default ];

  programs.opencodex = {
    enable = true;
    service.enable = true;

    # Merged over the current/default config before each service start.
    # Keep secrets out of the Nix store.
    settings = {
      port = 10100;
      hostname = "127.0.0.1";
    };

    # environment.OPENAI_API_KEY.file = config.sops.secrets.openai-api-key.path;
    # environment.OPENCODEX_HOME.value = "${config.home.homeDirectory}/.opencodex";
  };
}
```

The user service starts at login and restarts after failure:

```sh
systemctl --user status opencodex-proxy
ocx ready --wait
ocx gui
```

Do not run `ocx service install` when the module service is enabled: the module owns the `opencodex-proxy` unit declaratively.

## NixOS

The NixOS module runs a system service as an explicitly selected user:

```nix
{ inputs, pkgs, config, ... }:
{
  imports = [ inputs.opencodex.nixosModules.default ];

  programs.opencodex = {
    enable = true;
    service = {
      enable = true;
      user = "lukas";
      # Add clients which OpenCodex should discover from its service PATH.
      # path = [ pkgs.codex ];
      # openFirewall = true;
    };

    environment.OPENCODEX_API_AUTH_TOKEN.file =
      config.sops.secrets.opencodex-api-token.path;
  };
}
```

OpenCodex binds to loopback by default. Only use `openFirewall = true` together with a deliberate non-loopback configuration and API authentication.

## Configuration ownership

When `settings` is non-null and the service is enabled, the module recursively merges it over OpenCodex's current (or built-in default) configuration, validates the result, and imports it before every start. Declared fields are reasserted after a restart; dashboard changes to undeclared fields remain intact. Leave `settings = null` (the default) to manage configuration entirely through `ocx setup` or the dashboard.

Environment values are explicit so secrets need not enter the Nix store:

```nix
programs.opencodex.environment = {
  OPENCODEX_HOME.value = "/home/lukas/.opencodex";
  OPENCODEX_API_AUTH_TOKEN.file = config.sops.secrets.opencodex-token.path;
};
```

An environment file can be supplied instead:

```nix
programs.opencodex.environment = config.sops.templates.opencodex-env.path;
```

The service uses `OCX_SERVICE=1`, matching OpenCodex's own supervised-service mode. This preserves Codex routing across automatic restarts. After permanently disabling the service, run `ocx restore` if Codex should immediately return to its native provider.

## Overlay and library

```nix
nixpkgs.overlays = [ inputs.opencodex.overlays.default ];
environment.systemPackages = [ pkgs.opencodex ];
```

```nix
let
  ocx = inputs.opencodex.lib.mkOpenCodex {
    inherit pkgs;
    modules = [{
      opencodex.environment.OPENCODEX_HOME.value = "/srv/opencodex";
    }];
  };
in
ocx.package
```

Generate the option reference with `nix build .#docs-md`; it is written to `result/index.md`.

Maintainers can update the npm release, lockfile, generated Bun dependencies, and source hash with `nix run .#update`.
