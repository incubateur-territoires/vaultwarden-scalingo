#!/usr/bin/env bash
# Read what upstream publishes about the web vault of a Vaultwarden release.
# Pure readers of files: no network, so `make check` proves them offline. The
# update workflow does the downloads and calls these on what it downloaded.
#
#   scripts/upstream-web-vault.sh vault-version DockerSettings.yaml
#       the web vault version Vaultwarden pins (`vault_version:`), e.g. v2026.10.1
#   scripts/upstream-web-vault.sh sha256-of sha256sums.txt NAME
#       the checksum upstream lists for NAME in its sha256sums.txt
#   scripts/upstream-web-vault.sh commit-of ARCHIVE.tar.gz
#       the commit id that `git archive` wrote in the header of the archive
#
# A file that does not have exactly what is asked is refused: exit 1, the reason
# on stderr, nothing on stdout.
set -euo pipefail

fail() {
  echo " !     upstream-web-vault: $*" >&2
  exit 1
}

readable() {
  [ -f "$1" ] && [ -r "$1" ] || fail "cannot read $1"
}

vault_version_of() {
  local file="$1" lines count value
  readable "$file"
  # Top-level key only: a comment or an indented line is not the setting.
  lines="$(grep -E '^vault_version:' "$file" || true)"
  [ -n "$lines" ] || fail "no vault_version in $file"
  count="$(printf '%s\n' "$lines" | wc -l | tr -d ' ')"
  [ "$count" -eq 1 ] || fail "vault_version is set more than once in $file"
  value="${lines#vault_version:}"
  value="${value%%#*}" # a trailing comment
  value="$(printf '%s' "$value" | tr -d ' \t"'"'")"
  [[ $value =~ ^v[0-9]{4}\.[0-9]+\.[0-9]+$ ]] || fail "'$value' is not a web vault version (like v2026.10.1)"
  printf '%s\n' "$value"
}

# The lines of sha256sum are "<64 hex>  NAME" ("<64 hex> *NAME" in binary mode).
sha256_from_sums() {
  local file="$1" name="$2" found count sum
  readable "$file"
  found="$(NAME="$name" awk '
    { n = $0; sub(/^[^ ]+ [ *]/, "", n) }
    n == ENVIRON["NAME"] { print $1 }' "$file")"
  [ -n "$found" ] || fail "no checksum for $name in $file"
  count="$(printf '%s\n' "$found" | wc -l | tr -d ' ')"
  [ "$count" -eq 1 ] || fail "$name is listed more than once in $file"
  sum="$found"
  [[ $sum =~ ^[0-9a-f]{64}$ ]] || fail "the checksum listed for $name is not a sha256 (64 lowercase hex characters)"
  printf '%s\n' "$sum"
}

# GitHub builds source archives with `git archive`, which records the commit in
# the header of the tar. It is what ties the archive to a commit that the API
# names for a tag. (git does the reading: the pax header is not parsed here.)
archive_commit_id() {
  local file="$1" id
  readable "$file"
  id="$(gzip -dc "$file" 2> /dev/null | git get-tar-commit-id 2> /dev/null || true)"
  [[ $id =~ ^[0-9a-f]{40}$ ]] || fail "no commit id in $file (not a git archive)"
  printf '%s\n' "$id"
}

main() {
  case "${1:-}" in
    vault-version)
      [ "$#" -eq 2 ] || fail "usage: upstream-web-vault.sh vault-version DockerSettings.yaml"
      vault_version_of "$2"
      ;;
    sha256-of)
      [ "$#" -eq 3 ] || fail "usage: upstream-web-vault.sh sha256-of sha256sums.txt NAME"
      sha256_from_sums "$2" "$3"
      ;;
    commit-of)
      [ "$#" -eq 2 ] || fail "usage: upstream-web-vault.sh commit-of ARCHIVE.tar.gz"
      archive_commit_id "$2"
      ;;
    *) fail "usage: upstream-web-vault.sh vault-version|sha256-of|commit-of ARGS..." ;;
  esac
}

main "$@"
