#!/usr/bin/env bash
# Rewrite the value of one existing key of a KEY=VALUE file (VERSIONS), in place.
#
#   scripts/set-version.sh FILE KEY VALUE
#
# Only the line of KEY changes: comments, blank lines and order are kept. Refuses
# (exit 1, FILE untouched) an unknown or duplicated KEY, a KEY that is not an
# upper-case name, and a VALUE with a newline, a carriage return or '='. VALUE
# may be empty. It checks the shape of the line, not the meaning of the value:
# `make check` holds the rules of VERSIONS.
set -euo pipefail

fail() {
  echo " !     set-version: $*" >&2
  exit 1
}

[ "$#" -eq 3 ] || fail "usage: set-version.sh FILE KEY VALUE"
file="$1"
key="$2"
value="$3"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/kv.sh
. "$root/scripts/lib/kv.sh"

[[ $key =~ ^[A-Z][A-Z0-9_]*$ ]] || fail "$key is not a valid key name (upper case letters, digits and _)"
case "$value" in
  *$'\n'*) fail "the value of $key contains a newline" ;;
  *$'\r'*) fail "the value of $key contains a carriage return" ;;
  *=*) fail "the value of $key contains '='" ;;
esac

# read_kv explains an unreadable file and a duplicated key itself.
rc=0
read_kv "$file" "$key" > /dev/null || rc=$?
case "$rc" in
  0) ;;
  1) fail "unknown key $key in $file" ;;
  *) exit 1 ;;
esac

# The value goes through the environment: awk -v would interpret backslashes.
tmp="$(mktemp "$file.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
NEW_VALUE="$value" awk -v key="$key" '
  /^[[:space:]]*#/ { print; next }
  {
    i = index($0, "=")
    if (i > 0 && substr($0, 1, i - 1) == key) { print key "=" ENVIRON["NEW_VALUE"] } else { print }
  }' "$file" > "$tmp"
# Copy into FILE rather than rename over it: its mode and owner stay.
cat "$tmp" > "$file"
