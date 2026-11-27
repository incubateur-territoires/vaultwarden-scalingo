#!/usr/bin/env bash
# Read what upstream publishes about the web vault of a Vaultwarden release.
# Pure readers of files: no network, so `make check` proves them offline. The
# update workflow does the downloads and calls these on what it downloaded.
#
#   scripts/upstream-web-vault.sh vault-version DockerSettings.yaml
#       the web vault version Vaultwarden pins (`vault_version:`), e.g. v2026.10.1
#   scripts/upstream-web-vault.sh sha256-of sha256sums.txt NAME
#       the checksum upstream lists for NAME in its sha256sums.txt
#   scripts/upstream-web-vault.sh tree-of ARCHIVE.tar.gz
#       the git tree id of the files inside a source archive (the single
#       top-level directory of the archive is not part of it)
#
# A file that does not have exactly what is asked is refused: exit 1, the reason
# on stderr, nothing on stdout.
set -euo pipefail

fail() {
  echo " !     upstream-web-vault: $*" >&2
  exit 1
}

readable() {
  if [ ! -f "$1" ] || [ ! -r "$1" ]; then
    fail "cannot read $1"
  fi
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

# The git tree of the files in a source archive, as `git write-tree` computes
# it. GitHub builds the archive with `git archive`, so for a tag it is the tree
# of the tagged commit; the workflow compares it with the tree that the API
# gives for that commit. That ties every file to the commit. (The commit id in
# the header of the tar proves nothing: anyone who makes a tar can write it.)
# The archive is unpacked in a new directory and hashed with no filter, no
# ignore rule and no attribute of its own applied, so that what is hashed is
# what is in the tar. A tree that differs by design (export-ignore,
# export-subst in the repository) makes the comparison fail, never pass.
archive_tree_id() {
  local file="$1" dir tree
  readable "$file"
  dir="$(mktemp -d)"
  mkdir "$dir/files" "$dir/git"
  if ! gzip -dc "$file" 2> /dev/null | tar -x -f - -C "$dir/files" --strip-components=1 2> /dev/null; then
    rm -rf "$dir"
    fail "$file is not an archive that tar can read"
  fi
  # Hermetic git: no user or system configuration, nothing that rewrites files.
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1
  export GIT_DIR="$dir/git" GIT_WORK_TREE="$dir/files"
  cd "$dir/files"
  git init -q
  mkdir -p "$GIT_DIR/info"
  echo '* -text -filter -ident -working-tree-encoding' > "$GIT_DIR/info/attributes"
  tree=""
  if git -c core.autocrlf=false -c core.safecrlf=false add --all --force . 2> /dev/null; then
    tree="$(git write-tree 2> /dev/null || true)"
  fi
  rm -rf "$dir"
  [[ $tree =~ ^[0-9a-f]{40}$ ]] || fail "cannot compute the tree of $file"
  printf '%s\n' "$tree"
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
    tree-of)
      [ "$#" -eq 2 ] || fail "usage: upstream-web-vault.sh tree-of ARCHIVE.tar.gz"
      archive_tree_id "$2"
      ;;
    *) fail "usage: upstream-web-vault.sh vault-version|sha256-of|tree-of ARGS..." ;;
  esac
}

main "$@"
