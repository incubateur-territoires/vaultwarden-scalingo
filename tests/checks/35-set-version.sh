#!/usr/bin/env bash
# scripts/set-version.sh on temp copies of VERSIONS fixtures. Offline.

# shellcheck source=scripts/lib/kv.sh
. scripts/lib/kv.sh

# refuses SCRIPT REASON ARGS...: the script must fail and say REASON.
refuses() {
  local script="$1" reason="$2" err
  shift 2
  if err="$(bash "$script" "$@" 2>&1 > /dev/null)"; then
    problem "$script" "must refuse ($reason)"
  elif ! printf '%s' "$err" | grep -qF -- "$reason"; then
    problem "$script" "must say \"$reason\" (got: $err)"
  fi
}

set_version_check() {
  local script=scripts/set-version.sh work file sha before want
  sha=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  work="$(mktemp -d)"
  file="$work/VERSIONS"
  cp tests/fixtures/versions/ok-unpinned.env "$file"

  # A key is rewritten in place: only its line changes, comments and order stay.
  if ! bash "$script" "$file" RELEASE_TAG v1.2.3 > /dev/null 2>&1; then
    problem "$script" "exits non-zero when it sets a known key"
  fi
  if [ "$(read_kv "$file" RELEASE_TAG 2> /dev/null)" != "v1.2.3" ]; then
    problem "$script" "must set the value of the key"
  fi
  want="$(sed 's/^RELEASE_TAG=$/RELEASE_TAG=v1.2.3/' tests/fixtures/versions/ok-unpinned.env)"
  if [ "$(cat "$file")" != "$want" ]; then
    problem "$script" "must change only the line of the key (comments and order kept)"
  fi

  # The pin is two calls; the result passes the VERSIONS rules.
  bash "$script" "$file" RELEASE_ASSET_SHA256 "$sha" > /dev/null 2>&1
  expect_no_problem check_versions "$file"

  # A value can be replaced, and emptied.
  bash "$script" "$file" RELEASE_TAG v2.0.0 > /dev/null 2>&1
  [ "$(read_kv "$file" RELEASE_TAG 2> /dev/null)" = "v2.0.0" ] || problem "$script" "must replace a value already set"
  bash "$script" "$file" RELEASE_TAG "" > /dev/null 2>&1
  [ "$(read_kv "$file" RELEASE_TAG 2> /dev/null)" = "" ] || problem "$script" "must accept an empty value"

  # A value is never interpreted: backslashes and & stay as they are.
  bash "$script" "$file" RELEASE_TAG 'a\n&b' > /dev/null 2>&1
  [ "$(read_kv "$file" RELEASE_TAG 2> /dev/null)" = 'a\n&b' ] || problem "$script" "must store the value verbatim"

  # Refusals: non-zero, a reason on stderr, the file untouched.
  cp tests/fixtures/versions/ok-unpinned.env "$file"
  before="$(cat "$file")"
  refuses "$script" "unknown key" "$file" NOT_A_KEY v1
  refuses "$script" "newline" "$file" RELEASE_TAG "$(printf 'v1\nWEB_VAULT_SHA256=0')"
  refuses "$script" "'='" "$file" RELEASE_TAG "v1=2"
  refuses "$script" "carriage return" "$file" RELEASE_TAG "$(printf 'v1\r')"
  refuses "$script" "usage" "$file" RELEASE_TAG
  refuses "$script" "usage" "$file" RELEASE_TAG v1 extra
  refuses "$script" "not a valid key name" "$file" 'release_tag' v1
  refuses "$script" "cannot read" "$work/absent" RELEASE_TAG v1
  [ "$(cat "$file")" = "$before" ] || problem "$script" "a refused call must leave the file untouched"

  cp tests/fixtures/versions/duplicate-key.env "$file"
  refuses "$script" "more than once" "$file" WEB_VAULT_VERSION v2026.10.2
  rm -rf "$work"
}

set_version_check
