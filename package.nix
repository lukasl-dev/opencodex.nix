{
  lib,
  stdenv,
  fetchurl,
  bun2nix,
  bun,
  nodejs,
  makeWrapper,
  autoPatchelfHook,
  version,
  hash,
}:

let
  bunRuntimePackage =
    if stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isx86_64 then
      "bun-linux-x64"
    else if stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isAarch64 then
      "bun-linux-aarch64"
    else if stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isx86_64 then
      "bun-darwin-x64"
    else if stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isAarch64 then
      "bun-darwin-aarch64"
    else
      throw "OpenCodex does not have a bundled Bun runtime for ${stdenv.hostPlatform.system}";

  keyringRuntimePackage =
    if stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isx86_64 then
      "keyring-linux-x64-gnu"
    else if stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isAarch64 then
      "keyring-linux-arm64-gnu"
    else if stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isx86_64 then
      "keyring-darwin-x64"
    else if stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isAarch64 then
      "keyring-darwin-arm64"
    else
      throw "OpenCodex does not have a keyring runtime for ${stdenv.hostPlatform.system}";
in
stdenv.mkDerivation {
  pname = "opencodex";
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/@bitkyc08/opencodex/-/opencodex-${version}.tgz";
    inherit hash;
  };
  sourceRoot = "package";

  nativeBuildInputs = [
    bun2nix.hook
    bun
    makeWrapper
  ]
  ++ lib.optional stdenv.hostPlatform.isLinux autoPatchelfHook;

  buildInputs = lib.optional stdenv.hostPlatform.isLinux stdenv.cc.cc.lib;

  bunDeps = bun2nix.fetchBunDeps {
    bunNix = ./bun.nix;
  };

  bunInstallFlags = [
    "--linker=hoisted"
    "--frozen-lockfile"
  ]
  ++ lib.optional stdenv.hostPlatform.isDarwin "--backend=copyfile";

  dontUseBunBuild = true;
  dontUseBunCheck = true;
  dontUseBunPatch = true;

  postPatch = ''
    cp ${./bun.lock} bun.lock
  '';

  installPhase = ''
    runHook preInstall

    # The lock contains optional binaries for every npm platform. Keep only the
    # host runtime and link it at the location expected by the upstream launcher.
    find node_modules/@oven -mindepth 1 -maxdepth 1 ! -name ${lib.escapeShellArg bunRuntimePackage} -exec rm -rf {} +
    ln -s ../../@oven/${bunRuntimePackage}/bin/bun node_modules/bun/bin/bun

    find node_modules/@napi-rs -mindepth 1 -maxdepth 1 \
      ! -name keyring \
      ! -name ${lib.escapeShellArg keyringRuntimePackage} \
      -exec rm -rf {} +

    # Development-only compiler packages are not needed to execute the shipped
    # TypeScript through Bun; removing them also avoids retaining build-time Bun.
    rm -rf node_modules/@types node_modules/@typescript node_modules/typescript
    rm -f node_modules/.bin/tsc node_modules/.bin/tsserver

    # bun2nix patches dependency example scripts to its build-time fake Node.
    # They are shipped as part of runtime dependencies, so point them at the
    # package's actual Node instead of retaining the entire build-time Bun.
    grep -rlZ '/nix/store/[^/]*-bun-with-fake-node/bin/node' node_modules \
      | xargs -0 -r sed -i -E \
        's#/nix/store/[a-z0-9]+-bun-with-fake-node/bin/node#${nodejs}/bin/node#g'

    mkdir -p $out/bin $out/lib/opencodex
    cp -R . $out/lib/opencodex/

    makeWrapper ${nodejs}/bin/node $out/bin/ocx \
      --add-flags "$out/lib/opencodex/bin/ocx.mjs" \
      --set OPENCODEX_BUN_PATH "$out/lib/opencodex/node_modules/bun/bin/bun"
    ln -s ocx $out/bin/opencodex

    runHook postInstall
  '';

  meta = {
    description = "Universal provider proxy for OpenAI Codex and Claude Code";
    homepage = "https://github.com/lidge-jun/opencodex";
    license = lib.licenses.mit;
    mainProgram = "ocx";
    maintainers = [
      {
        name = "Lukas";
        email = "me@lukasl.dev";
        github = "lukasl-dev";
      }
    ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
