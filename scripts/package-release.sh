#!/usr/bin/env bash
# Assemble the release asset from a built binary and the upstream web vault.
#
#   scripts/package-release.sh BINARY WEB_VAULT_TARBALL OUT_DIR
#
# Writes OUT_DIR/vaultwarden-scalingo-x86_64-linux.tar.gz and OUT_DIR/SHA256SUMS.
# The asset has one top directory, extracted into the Scalingo build dir:
#   vaultwarden/vaultwarden      the binary
#   vaultwarden/web-vault/...    the web-vault/ directory of the upstream web vault tarball
#   vaultwarden/manifest         VAULTWARDEN_VERSION, WEB_VAULT_VERSION, SOURCE_COMMIT
# Verifies nothing itself: the caller checks the source and web vault checksums.
set -euo pipefail

ASSET_NAME=vaultwarden-scalingo-x86_64-linux.tar.gz

fail() {
  echo " !     $*" >&2
  exit 1
}

[ "$#" -eq 3 ] || fail "usage: package-release.sh BINARY WEB_VAULT_TARBALL OUT_DIR"
binary="$1"
web_vault_tarball="$2"
out_dir="$3"
[ -f "$binary" ] || fail "binary not found: $binary"
[ -f "$web_vault_tarball" ] || fail "web vault tarball not found: $web_vault_tarball"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/kv.sh
. "$root/scripts/lib/kv.sh"
# shellcheck source=scripts/lib/sha256.sh
. "$root/scripts/lib/sha256.sh"
vaultwarden_version="$(read_kv "$root/VERSIONS" VAULTWARDEN_VERSION)"
web_vault_version="$(read_kv "$root/VERSIONS" WEB_VAULT_VERSION)"
source_commit="${GITHUB_SHA:-$(git -C "$root" rev-parse HEAD)}"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/vaultwarden"
cp "$binary" "$stage/vaultwarden/vaultwarden"
chmod 755 "$stage/vaultwarden/vaultwarden"
# Extracted apart, then only web-vault/ is moved in: an entry of the tarball
# cannot replace the binary or the manifest.
mkdir "$stage/web"
tar -xzf "$web_vault_tarball" -C "$stage/web"
[ -d "$stage/web/web-vault" ] || fail "$web_vault_tarball has no web-vault/ directory"
mv "$stage/web/web-vault" "$stage/vaultwarden/web-vault"
{
  echo "VAULTWARDEN_VERSION=$vaultwarden_version"
  echo "WEB_VAULT_VERSION=$web_vault_version"
  echo "SOURCE_COMMIT=$source_commit"
} > "$stage/vaultwarden/manifest"

mkdir -p "$out_dir"
tar -czf "$out_dir/$ASSET_NAME" -C "$stage" vaultwarden
echo "$(sha256_of "$out_dir/$ASSET_NAME")  $ASSET_NAME" > "$out_dir/SHA256SUMS"
echo "-----> Packaged $out_dir/$ASSET_NAME (Vaultwarden $vaultwarden_version, web vault $web_vault_version)"
