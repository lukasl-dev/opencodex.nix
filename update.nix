{
  pkgs,
  bun2nix,
}:

pkgs.writeShellApplication {
  name = "opencodex-update";
  runtimeInputs = [
    pkgs.curl
    pkgs.gitMinimal
    pkgs.jq
    pkgs.nix
    bun2nix
  ];
  text = ''
    set -euo pipefail

    root="$(git rev-parse --show-toplevel)"
    cd "$root"

    metadata="$(curl --fail --silent --show-error https://registry.npmjs.org/@bitkyc08/opencodex)"
    version="$(jq -r '.["dist-tags"].latest' <<<"$metadata")"
    tarball="$(jq -r --arg version "$version" '.versions[$version].dist.tarball' <<<"$metadata")"
    hash="$(nix store prefetch-file --json "$tarball" | jq -r .hash)"

    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT

    curl --fail --silent --show-error --location \
      "https://raw.githubusercontent.com/lidge-jun/opencodex/v$version/bun.lock" \
      --output "$tmp/bun.lock"
    bun2nix --lock-file "$tmp/bun.lock" --output-file "$tmp/bun.nix"
    if [[ -n "$(tail -c1 "$tmp/bun.nix")" ]]; then
      printf '\n' >> "$tmp/bun.nix"
    fi

    mv "$tmp/bun.lock" bun.lock
    mv "$tmp/bun.nix" bun.nix
    jq -n --arg version "$version" --arg hash "$hash" \
      '{ version: $version, hash: $hash }' > VERSION.json

    echo "Updated OpenCodex to $version."
  '';
}
