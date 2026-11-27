#!/usr/bin/env bash
# Scalingo build: install the release of this repository that VERSIONS pins.
#
#   scripts/compile.sh BUILD_DIR CACHE_DIR ENV_DIR
#
# Downloads the release asset, refuses it unless its sha256 is the pinned one,
# and extracts it into BUILD_DIR (vaultwarden/ there becomes /app/vaultwarden/).
# A failed build leaves the running app untouched, so every failure exits 1.
#
# VAULTWARDEN_RELEASE_URL replaces the download URL; the offline tests set it
# to a file:// URL. Nothing sets it in production, and the pinned sha256 is
# checked whatever the source.
set -eu

ASSET_NAME=vaultwarden-scalingo-x86_64-linux.tar.gz

BUILD_DIR="${1:?usage: compile.sh BUILD_DIR CACHE_DIR ENV_DIR}"
CACHE_DIR="${2:?usage: compile.sh BUILD_DIR CACHE_DIR ENV_DIR}"

fail() {
  echo " !     $*" >&2
  exit 1
}

# shellcheck source=scripts/lib/kv.sh
. "$(dirname "$0")/lib/kv.sh"
# shellcheck source=scripts/lib/sha256.sh
. "$(dirname "$0")/lib/sha256.sh"

versions="$BUILD_DIR/VERSIONS"
repository="$(read_kv "$versions" RELEASE_REPOSITORY)" || fail "Cannot read RELEASE_REPOSITORY from VERSIONS."
tag="$(read_kv "$versions" RELEASE_TAG)" || fail "Cannot read RELEASE_TAG from VERSIONS."
pin="$(read_kv "$versions" RELEASE_ASSET_SHA256)" || fail "Cannot read RELEASE_ASSET_SHA256 from VERSIONS."

if [ -z "$tag" ]; then
  fail "VERSIONS pins no release yet (RELEASE_TAG is empty). Publish a release of this repository, then merge the pull request that pins it."
fi
if [ -z "$pin" ]; then
  fail "VERSIONS sets RELEASE_TAG but RELEASE_ASSET_SHA256 is empty. Refusing to install a release that is not verified."
fi

url="${VAULTWARDEN_RELEASE_URL:-https://github.com/$repository/releases/download/$tag/$ASSET_NAME}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# CACHE_DIR may be shared with other buildpacks: keep ours in a subdirectory.
cache="$CACHE_DIR/vaultwarden"
mkdir -p "$cache"
cached="$cache/$pin.tar.gz"
asset="$work/$ASSET_NAME"

# One asset per pin in the cache: drop what an earlier pin left.
find "$cache" -maxdepth 1 -type f -name '*.tar.gz' ! -name "$pin.tar.gz" -delete

if [ -f "$cached" ] && [ "$(sha256_of "$cached")" = "$pin" ]; then
  echo "-----> Using the cached release asset"
  cp "$cached" "$asset"
else
  echo "-----> Downloading release $tag"
  case "$url" in
    file://*)
      cp "${url#file://}" "$asset" 2> /dev/null ||
        fail "Could not download $url. Check that release $tag exists and has its assets."
      ;;
    *)
      curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --location --retry 3 \
        --connect-timeout 30 --max-time 300 --output "$asset" "$url" ||
        fail "Could not download $url. Check that release $tag exists and has its assets."
      ;;
  esac
fi

actual="$(sha256_of "$asset")"
if [ "$actual" != "$pin" ]; then
  fail "Checksum mismatch for $ASSET_NAME: expected $pin, got $actual. Refusing to install."
fi
cp "$asset" "$cached"

rm -rf "${BUILD_DIR:?}/vaultwarden"
tar -xzf "$asset" -C "$BUILD_DIR" ||
  fail "Could not extract $ASSET_NAME into the build directory. Check that the build has disk space left, then deploy again."

# Keep what the binary says: a missing library, or a stack it cannot run on,
# shows there and nowhere else.
status=0
said="$("$BUILD_DIR/vaultwarden/vaultwarden" --version 2>&1)" || status=$?
if [ "$status" -ne 0 ]; then
  echo "       vaultwarden --version exited with status $status:" >&2
  printf '%s\n' "$said" | sed 's/^/       /' >&2
  fail "The Vaultwarden binary does not run on stack ${STACK:-unknown}. Supported stacks: scalingo-24, scalingo-26."
fi

version="$(read_kv "$BUILD_DIR/vaultwarden/manifest" VAULTWARDEN_VERSION)" || version=unknown
web_version="$(read_kv "$BUILD_DIR/vaultwarden/manifest" WEB_VAULT_VERSION)" || web_version=unknown
echo "-----> Installed Vaultwarden $version with web vault $web_version from release $tag"
