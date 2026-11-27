#!/usr/bin/env bash
# Pin a published release in VERSIONS. Run by the pin job of release.yml.
#
#   scripts/pin-release.sh FILE TAG SHA256SUMS REPOSITORY
#
# Sets RELEASE_TAG to TAG and RELEASE_ASSET_SHA256 to the checksum on the first
# line of SHA256SUMS (the file package-release.sh wrote and the release
# carries), through set-version.sh, and prints that checksum. Refuses (exit 1,
# FILE untouched) a TAG that is not a plain tag name, a SHA256SUMS that does not
# start with a sha256, a REPOSITORY (the repository the workflow runs in) other
# than the RELEASE_REPOSITORY of FILE, and a FILE that already pins this TAG
# with this checksum. It does not check the asset against SHA256SUMS: the
# workflow does, with sha256sum, before it calls this.
set -euo pipefail

fail() {
  echo " !     pin-release: $*" >&2
  exit 1
}

[ "$#" -eq 4 ] || fail "usage: pin-release.sh FILE TAG SHA256SUMS REPOSITORY"
file="$1"
tag="$2"
sums="$3"
repository="$4"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/kv.sh
. "$root/scripts/lib/kv.sh"

[[ $tag =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail "The tag '$tag' is not a plain tag name: pin it by hand."

[ -f "$sums" ] && [ -r "$sums" ] || fail "cannot read $sums"
sha256=""
read -r sha256 _ < "$sums" || [ -n "$sha256" ] || true
[[ $sha256 =~ ^[0-9a-f]{64}$ ]] || fail "$sums does not start with a sha256."

# read_kv explains an unreadable file and a duplicated key itself.
pinned_repository="$(read_kv "$file" RELEASE_REPOSITORY)" || fail "Cannot read RELEASE_REPOSITORY from $file."
if [ "$pinned_repository" != "$repository" ]; then
  fail "RELEASE_REPOSITORY is $pinned_repository but this workflow runs in ${repository:-an unknown repository} (a fork?): pinning its release would point Scalingo builds at a release that does not exist in $pinned_repository. Pin by hand, or change RELEASE_REPOSITORY first."
fi

current_tag="$(read_kv "$file" RELEASE_TAG)" || fail "Cannot read RELEASE_TAG from $file."
current_sha256="$(read_kv "$file" RELEASE_ASSET_SHA256)" || fail "Cannot read RELEASE_ASSET_SHA256 from $file."
if [ "$current_tag" = "$tag" ] && [ "$current_sha256" = "$sha256" ]; then
  fail "$file already pins $tag with this checksum: nothing to pin (its pull request was probably merged)."
fi

"$root/scripts/set-version.sh" "$file" RELEASE_TAG "$tag"
"$root/scripts/set-version.sh" "$file" RELEASE_ASSET_SHA256 "$sha256"
echo "$sha256"
